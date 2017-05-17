#!/usr/bin/env ruby

require 'json'
require 'date'
require 'csv'
require 'sqlite3'
require 'mechanize'


pages = 5
intervals = 86400 # scraping cycle is 24 hours (86400 seconds)


class Scraper < Mechanize
  Dbname = "data.db"

  attr_accessor :url, :pages, :outfilename
  attr_reader :db

  def initialize(url, pages)
    super()
    self.user_agent_alias = 'Mac Safari'
    self.robots = false
    # self.open_timeout = 30
    # self.read_timeout = 30

    @url = url
    @pages = pages
    @outfilename = "output#{Time.now.strftime('%Y%m%d%H%M%S')}.csv"
    @db = SQLite3::Database.new Dbname

    create_table

    # get(url)
    # @item_number = page.search('div.product-search-form__nav-total').text.tr(",","").to_i
    # @page_number = page.search('span.page-numbers').text.match(/of (\d+)/)[1].to_i
  end

  def create_table
    def sql(tb)
      <<-SQL
        CREATE TABLE IF NOT EXISTS #{tb} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          unique_id varchar(255),
          category varchar(255),
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

    db.execute sql("first_day_products")
    db.execute sql("tmp_products")
    db.execute sql("newly_products")

    categories_sql =<<-SQL
      CREATE TABLE IF NOT EXISTS categories (
        category varchar(512)
      );
    SQL
    db.execute categories_sql

    sold_sql =<<-SQL
      CREATE TABLE IF NOT EXISTS sold_products (
        unique_id varchar(255)
      );
    SQL
    db.execute sold_sql
  end

  def check_available(product_url)
    get(product_url)
    sleep 5
    product = page.content.match(/data-product="(.+?)"/)[1].gsub("&quot;", '"')
    product = JSON.parse(product)
    puts "> #{[product["name"], product["sale_price"], product["release_date"], product["available"]].join(',')}"
    [product["available"], product["unique_id"]]
  end

  # get 5 pages every day, and insert product items into tmp_products table
  def process(table_name = "tmp_products")
    db.execute "DELETE FROM #{table_name};"
    db.execute "VACUUM" # follow DELETE to clear unused space

    (1..pages).each do |index|
      sufix = (url =~ /\?.+/) ? "&page=" : "?page="
      page_link = url + sufix + "#{index}"
      get(page_link)

      # puts "page #{index}: #{page_link}"

      seq = 1
      page.search('div.product-card__details a').each do |link|
        product_url = (page.uri + link.attribute('href')).to_s

        begin
          transact do
            click link
            # Do stuff, maybe click more links.
            product = page.content.match(/data-product="(.+?)"/)[1].gsub("&quot;", '"')
            product = JSON.parse(product)

            if product["available"] == 'N'
              # speed = (Date.parse(Time.now.to_s) - Date.parse(product["release_date"])).ceil
              speed = (Date.parse(Time.now.to_s) - Date.parse(product["release_date"])).round
            else
              speed = ""
            end

            row = nil, product["unique_id"], url, product["name"], product["price"], product["sale_price"], speed, product_url, product["release_date"], product["available"]
            db.execute "insert into #{table_name} values ( ?, ?, ? , ? , ? , ? , ? , ? , ? , ? )", row

            puts "page#{index}:#{seq}> #{[product["name"], product["sale_price"], product["release_date"], product["available"]].join(',')}"
            seq += 1
          end
          # Now we're back at the original page.

        rescue => e
          $stderr.puts "#{e.class}: #{e.message}"
        end
      end
    end
    # sleep 5 if index % 7 == 0
  end

  # reset scraper, delete data.db file including all scraped data.
  def self.reset
    `rm #{Dbname}`
    puts "The scraper is reseted. All scraped data have been delete!"
  end

  # add new category
  def init_category #(category)
    # row = db.get_first_row("select * from categories where category='#{category}'")
    # if row.nil?
    #   db.execute "INSERT INTO categories (category) values(#{category});"
    #   puts "the category is saved."
    # else
    #   puts "this category has been added."
    #   return
    # end

    puts "start scraping filtering data..."
    process
    sql = <<-SQL
      INSERT INTO first_day_products (unique_id, category, name, price, sale_price, speed, url, release_date, available)
      SELECT a.unique_id, a.category, a.name, a.price, a.sale_price, a.speed, a.url, a.release_date, a.available FROM tmp_products a
      WHERE NOT EXISTS (select 1 from first_day_products b where a.unique_id = b.unique_id);
    SQL
    db.execute sql
  end

  def start
    puts "start scraping..."
    process
    puts "scraping done!"

    puts "start filtering data..."
    # filter product items from first_day_table
    sql = <<-SQL
      DELETE FROM tmp_products
      WHERE EXISTS (SELECT 1 FROM first_day_products a WHERE a.unique_id = tmp_products.unique_id);
    SQL
    db.execute sql
    db.execute "VACUUM" # follow DELETE to clear unused space

    # filter product items from newly_table
    sql = <<-SQL
      DELETE FROM newly_products
      WHERE EXISTS (SELECT 1 FROM first_day_products a WHERE a.unique_id = newly_products.unique_id);
    SQL
    db.execute sql
    db.execute "VACUUM" # follow DELETE to clear unused space

    puts "start generating newly-posted..."
    sql = <<-SQL
      INSERT INTO newly_products (unique_id, category, name, price, sale_price, speed, url, release_date, available)
      SELECT a.unique_id, a.category, a.name, a.price, a.sale_price, a.speed, a.url, a.release_date, a.available FROM tmp_products a
      WHERE NOT EXISTS (select 1 from newly_products b where a.unique_id = b.unique_id)
    SQL
    db.execute sql

    sql = <<-SQL
      UPDATE newly_products SET available = 
      (SELECT a.available FROM tmp_products a where a.unique_id = newly_products.unique_id)
      WHERE EXISTS (select 1 from tmp_products a where a.unique_id = newly_products.unique_id)
    SQL
    db.execute sql

    sql = <<-SQL
      SELECT * FROM newly_products a WHERE a.available = 'Y'
      AND NOT EXISTS (select 1 from tmp_products b where a.unique_id = b.unique_id)
    SQL
    db.execute sql do |row|
      available, unique_id = check_available row[7] # product url

      if available == 'N'
        # speed = (Date.parse(Time.now.to_s) - Date.parse(product["release_date"])).ceil
        speed = (Date.parse(Time.now.to_s) - Date.parse(row[8])).round
      else
        speed = ""
      end

      db.execute "UPDATE newly_products SET available=?, speed=?  where unique_id=?", available, speed, unique_id
    end

    puts "start filtering sold products..."
    sql = <<-SQL
      DELETE FROM newly_products
      WHERE EXISTS (select 1 from sold_products a where a.unique_id = newly_products.unique_id)
    SQL
    db.execute sql

    puts "start generating CSV file..."
    sql = <<-SQL
      SELECT * FROM newly_products order by release_date desc
    SQL
    CSV.open(outfilename, 'w+') do |csv|
      csv << ["name", "sale_price", "speed", "url"]
      db.execute(sql) do |row|
        csv << [row[3], row[5], row[6], row[7]]
      end
    end
    puts "the file name is #{outfilename}"

    puts "start updating sold products..."
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

  def self.outputfile
    db = SQLite3::Database.new Dbname
    sql = <<-SQL
      SELECT * FROM newly_products order by release_date desc
    SQL
    filename = "output#{Time.now.strftime('%Y%m%d%H%M%S')}.csv"
    CSV.open(filename, 'w+') do |csv|
      csv << ["name", "sale_price", "speed", "url"]
      db.execute(sql) do |row|
        csv << [row[3], row[5], row[6], row[7]]
      end
    end
    puts "the file name is #{filename}"
  end
end

# categories = ["https://www.therealreal.com/shop/women/handbags"]
# categories = ["https://www.therealreal.com/sales/womens-jewelry?taxons%5B%5D=759"]
# categories = ["https://www.therealreal.com/sales/new-arrivals-fine-watches-1449?taxons%5B%5D=760"]

if ARGV[0].chomp('\n').downcase == 'reset'
  Scraper.reset
  exit
end

if ARGV[0] == 'add-filter'
  if ARGV.length != 2
    puts "Please provide category URL."
  else
    Scraper.new(ARGV[1], pages).init_category
  end
  exit
end

if ARGV[0] == 'outfile'
  Scraper.outputfile
  exit
end

while true
  if ARGV[0].nil?
    puts "please provide URL!"
    exit
  end

  Scraper.new(ARGV[0], pages).start
  puts "waiting for next scraping..."
  sleep intervals
end
