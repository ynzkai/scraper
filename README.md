###############################################
Usage Of Scraper
###############################################


How to scrape items:
1. On the first day, scrape the items that needs to be filtered

 ruby scraper.rb add-filter URL

   The URL is category link

2. The next day, scrape 5 pages, and remove items that scraped on the first day.

 ruby scraper.rb URL

3. Keep scraper.rb running, and it will automatically fetch 5 pages every 24 hours.
   or you can also close it and the next day re-run it by typing: ruby scraper.rb URL


Other features
1. Reset the Scraper

   ruby scraper.rb reset

   This command clears all filtered and retrieved data, so use it with caution.

2. Add data that needs to be filtered

   ruby scraper.rb add-filter URL

   This command will add 5 pages of items corresponding to the URL to the filter library.

3. Export the newly-posted items to the CSV file

   ruby scraper.rb outfile

   At any time want to look up newly-posted items, use this command to export it. it does not link to internet.

