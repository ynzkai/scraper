#! /usr/bin/env ruby

require 'json'
require 'date'
require 'csv'
require 'sqlite3'
require 'mechanize'

class Scraper < Mechanize
  Dbname = "data.db"

  attr_accessor :url, :pages, :outfilename
  attr_reader :db

  def initialize(url)
    super
    self.user_agent_alias = 'Mac Safari'
    self.robots = false
    # self.open_timeout = 30
    # self.read_timeout = 30

    @url = url
    @pages = 1
    @outfilename = "output#{Time.now.strftime('%Y%m%d%H%M%S')}.csv"
    @db = SQLite3::Database.new Dbname

    create_table

    status = db.get_first_value("select * from scraper_status")
    if status.nil?
      db.execute "INSERT INTO scraper_status (inited) values('N');"
    end

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
          available varchar(1)
        );
      SQL
    end

    db.execute sql("first_day_products")
    db.execute sql("every_day_products")
    db.execute sql("newly_products")
    db.execute sql("sold_products")

    scraper_sql =<<-SQL
      CREATE TABLE IF NOT EXISTS scraper_status (
        inited varchar(5)
      );
    SQL
    db.execute scraper_sql
  end


  def process(table_name)

    #category = url.match(/\.com\/(.+)\?/)[1]
    #category = url.match(/\.com\/(.+)$/)[1] unless category
    category = url.match(/\.com\/(.+)/)[1]
    category.chomp! '/'

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
              speed = (Date.parse(Time.now.to_s) - Date.parse(product["release_date"])).ceil
            else
              speed = ""
            end

            row = nil, product["unique_id"], category, product["name"], product["price"], product["sale_price"], speed, product_url, product["release_date"], product["available"]
            db.execute "insert into #{table_name} values ( ?, ?, ? , ? , ? , ? , ? , ? , ? , ? )", row

            puts "page#{index}:#{seq}> #{[product["name"], product["sale_price"], product["release_date"]].join(',')}"
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

  def self.reset
    # puts "You are going to delete ALL scraped data, are you sure?(y/n)"
    `rm #{Dbname}`
    puts "The scraper is reseted. All scraped data have been delete!"
  end

  def start
    puts "start scraping..."

    status = db.get_first_value("select * from scraper_status")

    if status == 'N'
      db.execute "DELETE FROM first_day_products;"
      db.execute "VACUUM" # follow DELETE to clear unused space
      process "first_day_products"
      db.execute "UPDATE scraper_status SET inited = 'Y';"
    else
      db.execute "DELETE FROM every_day_products;"
      db.execute "VACUUM" # follow DELETE to clear unused space
      process "every_day_products"

      sql = <<-SQL
        INSERT INTO newly_products
        SELECT * FROM every_day_products
        EXCEPT
        SELECT * FROM first_day_products
        EXCEPT
        SELECT * FROM newly_products    
      SQL
      db.execute sql

      sql = <<-SQL
        INSERT INTO sold_products
        SELECT * FROM every_day_products WHERE available = 'N'
      SQL
      db.execute sql

      sql = <<-SQL
        DELETE FROM newly_products
        WHERE EXISTS (SELECT 1 FROM every_day_products WHERE newly_products.unique_id = every_day_products.unique_id AND available = 'N')
      SQL
      db.execute sql


      sql = <<-SQL
        SELECT * FROM newly_products UNION ALL
        SELECT * FROM sold_products
      SQL
      db.execute(sql) do |row|
        CSV.open(outfilename, 'w+') do |csv|
          csv << ["name", "sale_price", "speed", "url"]
          csv << [row[3], row[5], row[6], row[7]]
        end
      end

    end

    puts "scraping done!"
  end

  def self.outputfile
    db = SQLite3::Database.new Dbname
    sql = <<-SQL
      SELECT * FROM newly_products UNION ALL
      SELECT * FROM sold_products
    SQL
    db.execute(sql) do |row|
      CSV.open("output.csv", 'w+') do |csv|
        csv << ["name", "sale_price", "speed", "url"]
        csv << [row[3], row[5], row[6], row[7]]
      end
    end
  end
end

# categories = ["https://www.therealreal.com/shop/women/handbags"]
# categories = ["https://www.therealreal.com/sales/womens-jewelry?taxons%5B%5D=759"]
# categories = ["https://www.therealreal.com/sales/new-arrivals-fine-watches-1449?taxons%5B%5D=760"]
categories = ARGV

if ARGV[0].chomp('\n').downcase == 'reset'
  # puts "You are deleting reset scraper, all scraped data will be deleted, are you sure?(y/n) "
  Scraper.reset
  exit
end

while true
  Scraper.new(categories[0]).start
  puts "waiting for next scraping..."
  sleep 86400 # scraping cycle is one day (86400 seconds)
end

