# filecoin-uploader

# Get started
## Setup MySQL server
```
sudo apt update
sudo apt install mysql-server
# Setup root user and password
sudo mysql_secure_installation
sudo mysql
mysql> CREATE DATABASE lotus;
mysql> GRANT ALL PRIVILEGE ON *.* TO 'root'@'localhost';
# Test mysql connection
mysql -u root -p
```
## Setup filecoin-uploader
```
git clone https://github.com/xinaxu/filecoin-uploader.git
cd filecoin-uploader
# Change MySQL connection
nano database/database.rb
# Change your own parameters
nano start.rb
# Install Ruby and gems
sudo apt install ruby ruby-dev libmysqlclient-dev
sudo gem install jsonrpc-client activerecord parallel
```

## Start
```
./start.rb
```

## Feature
* Miner management
  - Continuously update miner info and filter miner based on piece size and price
  - Miners with higher storage and retrieval success will have a higher chance of being used
  - Exclude own miner for slingshot rule compliance
* File management
  - Cotinuously scan the folder for any new data and import to database and lotus
* Deal management
  - Track deal state and slash state, maintain a set number of copies
* Retrieval management
  - Track the retrieval state for each deal
