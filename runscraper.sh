#!/bin/bash


export PATH="/usr/local/rvm/gems/ruby-2.3.3/bin:/usr/local/rvm/gems/ruby-2.3.3@global/bin:/usr/local/rvm/rubies/ruby-2.3.3/bin:$PATH"
export GEM_HOME='/usr/local/rvm/gems/ruby-2.3.3'
export GEM_PATH='/usr/local/rvm/gems/ruby-2.3.3:/usr/local/rvm/gems/ruby-2.3.3@global'
export MY_RUBY_HOME='/usr/local/rvm/rubies/ruby-2.3.3'
export IRBRC='/usr/local/rvm/rubies/ruby-2.3.3/.irbrc'
unset MAGLEV_HOME
unset RBXOPT
export RUBY_VERSION='ruby-2.3.3'


/usr/local/rvm/rubies/ruby-2.3.3/bin/ruby /root/scraper/scraper.rb https://www.therealreal.com/sales/womens-jewelry?taxons%5B%5D=759 https://www.therealreal.com/sales/new-arrivals-watches-4172?taxons%5B%5D=760 https://www.therealreal.com/shop/women/handbags https://www.therealreal.com/sales/new-arrivals-fine-watches-1449?taxons%5B%5D=760 5 N blake.vac@gmail.com houseeffect12
