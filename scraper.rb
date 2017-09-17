#!/usr/bin/env ruby

require 'json'
require 'date'
require 'csv'
require 'sqlite3'
require 'mechanize'
require 'mail'

require File.expand_path('proxies.rb', __dir__)

class Scraper < Mechanize
  Dbname = "data.db"
  SLEEP_SECONDS = 1
  ITEMS_PER_PROXY = 5

  Proxies = ::Proxies

  attr_accessor :url, :pages, :outfilename
  attr_reader :db

  def initialize(url, pages)
    super()
    self.user_agent_alias = 'Mac Safari'
    self.robots = false
    # self.open_timeout = 30
    # self.read_timeout = 30
    self.request_headers[SecureRandom.hex(10)] = SecureRandom.hex(10)

    @url = url
    @pages = pages
    # @outfilename = "output#{Time.now.strftime('%Y%m%d%H%M%S')}.csv"
    @outfilename = "output.csv"
    @db = SQLite3::Database.new Dbname
    @current_proxy_index = 0
    @get_count = 1

:qa
    create_table

  end

  def get(uri, parameters = [], referer = nil, headers = {})
    isFailed = false
    begin
      if @get_count % (ITEMS_PER_PROXY+1) == 0 or isFailed
        @current_proxy_index = 0 if @current_proxy_index >= Proxies.size
        set_proxy(*Proxies[@current_proxy_index])
        prompt "set proxy IP: #{Proxies[@current_proxy_index]}"
        @current_proxy_index += 1
        @get_count = 1 unless isFailed
      end
      begin
        _page = super
        isFailed = _page.nil?
      rescue => e
        puts e.message
        isFailed = true
      end
    end while isFailed
    @get_count += 1
    _page
  end

  def create_table
    def sql(tb)
      <<-SQL
        CREATE TABLE IF NOT EXISTS #{tb} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          unique_id varchar(255),
          category varchar(255),
          categories varchar(255),
          name varchar(255),
          price decimal(10,2),
          sale_price decimal(10,2),
          speed int,
          url varchar(512),
          release_date varchar(100),
          available varchar(10)
        );
      SQL
    end

    db.execute sql("tmp_products")
    db.execute sql("newly_products")

    sold_sql =<<-SQL
      CREATE TABLE IF NOT EXISTS sold_products (
        unique_id varchar(255)
      );
    SQL
    db.execute sold_sql
  end

  def check_available(product_url)
    begin
      get(product_url)
      # sleep SLEEP_SECONDS
      product = page.content.match(/data-product="(.+?)"/)[1].gsub("&quot;", '"')
      product = JSON.parse(product)
      prompt "> #{[product["name"], product["sale_price"], product["release_date"], product["available"]].join(',')}"
      product["available"]
    rescue => e
      $stderr.puts "#{e.class}: #{e.message}"
      'Y'
    end
  end

  # get 5 pages every day, and insert product items into tmp_products table
  def process(table_name = "tmp_products")
    db.execute "DELETE FROM #{table_name};"
    db.execute "VACUUM" # follow DELETE to clear unused space

    (1..pages).each do |index|
      sufix = (url =~ /\?.+/) ? "&page=" : "?page="
      page_link = url + sufix + "#{index}"
      get(page_link)
      # sleep SLEEP_SECONDS

      seq = 1
      page.search('div.product-card__details a').each do |link|
        product_url = (page.uri + link.attribute('href')).to_s

        # break if seq == 20

        begin
          transact do
            click link
	    # sleep SLEEP_SECONDS
            # Do stuff, maybe click more links.
            product = page.content.match(/data-product="(.+?)"/)[1].gsub("&quot;", '"')
            product = JSON.parse(product)

            if product["available"] == 'N'
              # speed = (Date.parse(Time.now.to_s) - Date.parse(product["release_date"])).ceil
              speed = (Date.parse(Time.now.to_s) - Date.parse(product["release_date"])).round
            else
              speed = ""
            end

            categories = product_url.match(/.+products\/(.*)/)[1].split("/")[0..-2].join(",")

            row = nil, product["unique_id"], url, categories, product["name"], product["price"], product["sale_price"], speed, product_url, product["release_date"], product["available"]
            db.execute "insert into #{table_name} values ( ?, ?, ?, ? , ? , ? , ? , ? , ? , ? , ? )", row

            prompt "page#{index}:#{seq}> #{[product["name"], product["sale_price"], product["release_date"], product["available"]].join(',')}"
            seq += 1
          end
          # Now we're back at the original page.

        rescue => e
          $stderr.puts "#{e.class}: #{e.message}"
        end
      end
    end
    # sleep 1 if index % 7 == 0
  end


  # reset scraper, delete data.db file including all scraped data.
  def self.reset
    # `rm #{Dbname}`
    `rm data*`
    puts "The scraper is reseted. All scraped data have been delete!"
  end


  def start(cate)
    prompt "start scraping..."
    process
    prompt "scraping done!"

    prompt "start processing items..."

    # filter product items from newly_table
    # sql = <<-SQL
    #   DELETE FROM newly_products
    #   WHERE EXISTS (SELECT 1 FROM first_day_products a WHERE a.unique_id = newly_products.unique_id);
    # SQL
    # db.execute sql
    # db.execute "VACUUM" # follow DELETE to clear unused space

    # add newly items
    sql = <<-SQL
      INSERT INTO newly_products (unique_id, category, categories, name, price, sale_price, speed, url, release_date, available)
      SELECT a.unique_id, a.category, categories, a.name, a.price, a.sale_price, a.speed, a.url, a.release_date, a.available FROM tmp_products a
      WHERE NOT EXISTS (select 1 from newly_products b where a.unique_id = b.unique_id)
    SQL
    db.execute sql

    # update old items' available state
    sql = <<-SQL
      UPDATE newly_products SET available = 
      (SELECT a.available FROM tmp_products a where a.unique_id = newly_products.unique_id)
      WHERE EXISTS (select 1 from tmp_products b where b.unique_id = newly_products.unique_id)
    SQL
    db.execute sql

    sql = <<-SQL
      SELECT * FROM newly_products a WHERE a.available = 'Y'
      AND NOT EXISTS (select 1 from tmp_products b where a.unique_id = b.unique_id)
      AND a.category='#{cate}'
    SQL
    db.execute sql do |row|
      available = check_available row[8] # product url

      if available == 'N'
        # speed = (Date.parse(Time.now.to_s) - Date.parse(product["release_date"])).ceil
        speed = (Date.parse(Time.now.to_s) - Date.parse(row[9])).round
      else
        speed = ""
      end

      db.execute "UPDATE newly_products SET available=?, speed=?  where unique_id=?", available, speed, row[1]
    end

    # sold items don't output repeatedly
    sql = <<-SQL
      DELETE FROM newly_products
      WHERE EXISTS (select 1 from sold_products a where a.unique_id = newly_products.unique_id)
    SQL
    db.execute sql
    db.execute "VACUUM" # follow DELETE to clear unused space

    # delete duplicated items
    sql = <<-SQL
      DELETE FROM newly_products
      WHERE rowid not in ( select min(rowid) from newly_products group by unique_id)
    SQL
    db.execute sql
    db.execute "VACUUM" # follow DELETE to clear unused space
  end

  def finish
    # record sold items
    sql = <<-SQL
      INSERT INTO sold_products (unique_id)
      select a.unique_id from newly_products a 
      WHERE a.available = 'N'
      AND NOT EXISTS (select 1 from sold_products b where a.unique_id = b.unique_id)
    SQL
    db.execute sql

    db.execute "DELETE FROM newly_products WHERE available = 'N'"
    db.execute "VACUUM" # follow DELETE to clear unused space
  end

  def self.outputfile(cate = nil)
    db = SQLite3::Database.new Dbname
    if cate
      sql = <<-SQL
        SELECT * FROM newly_products where category='#{cate}' order by release_date desc
      SQL
    else
      sql = <<-SQL
        SELECT * FROM newly_products  order by release_date desc
      SQL
    end
    filename = "output#{Time.now.strftime('%Y%m%d%H%M%S')}.csv"
    CSV.open(filename, 'w+') do |csv|
      csv << ["categories", "name", "sale_price", "speed", "url"]
      db.execute(sql) do |row|
        csv << [row[3], row[4], row[6], row[7], row[8]]
      end
    end
    prompt "the file name is #{filename}"
    filename
  end

end


if ARGV[0].chomp('\n').downcase == 'reset'
  Scraper.reset
  exit
end


if ARGV[0].chomp('\n').downcase == 'outfile'
  Scraper.outputfile
  exit
end

# categories = ["https://www.therealreal.com/shop/women/handbags"]
# categories = ["https://www.therealreal.com/sales/womens-jewelry?taxons%5B%5D=759"]
# categories = ["https://www.therealreal.com/sales/new-arrivals-fine-watches-1449?taxons%5B%5D=760"]

password = ARGV.pop
email = ARGV.pop
flag =  ARGV.pop
pages =  ARGV.pop.to_i

define_method(:prompt) do |message|
  puts message if flag == "Y"
end

ARGV.each do |url|
 
  begin
    scraper = Scraper.new(url, pages)
    scraper.start(url)
    filename = Scraper.outputfile(url)
    scraper.finish

    prompt "sending email..."
    message = url

    options = { address:              "smtp.gmail.com",
                port:                 587,
                domain:               'gmail.com',
                user_name:            email,
                password:             password,
                authentication:       'login',
                enable_starttls_auto: true }

    Mail.defaults do
      delivery_method :smtp, options
    end

    mail = Mail.new do
      from     email
      to       email
      subject  "csv file (#{url})"
      body     ''
      add_file :filename => 'output.csv', :content => ::File.read(filename)
    end

    mail.deliver

  rescue => e
    $stderr.puts "#{e.class}: #{e.message}"
  end

  `rm #{filename}`
end



