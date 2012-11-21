source "http://rubygems.org/"

ruby "1.9.3"

gem "thin"
gem "sinatra"
gem "datamapper"

group :development, :test do
  gem 'sqlite3'
  gem "dm-sqlite-adapter"
end
group :production do
  gem 'pg'
  gem "dm-postgres-adapter"
end