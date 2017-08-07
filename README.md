# Usage Of Scraper

### desktop version
ruby scraper_client.rb URL URL... 5

### server version

##### show prompt
ruby scraper.rb URL URL... 5 Y email password 

##### selient
ruby scraper.rb URL URL... 5 N email password 

### common command

##### reset database
ruby scraper.rb reset

##### output file
ruby scraper.rb outfile


### run scraper everyday
vim /etc/crontab

5 13 * * * root /root/scraper/runscraper.sh >> /root/scraper/script_out.log 2>&1
