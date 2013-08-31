#!/usr/bin/env ruby

require 'mongo'
require 'bson'
require 'json'
require 'openssl'
require 'base64'

include Mongo # Import mongo symbols for convenience

class Topic
  attr_accessor :name, :history, :last_updated, :count

  def initialize(name, time = nil, history = nil)
    @name = name
    @history = Array.new
    @history.push(history) unless history.nil?
    @last_updated = time.nil? ? Time.now : time 
    @count = @history.count
    
  end

  def add(entry)
    @history.push(entry)
    @count += 1
  end
  
  def read
    @history
  end
  
end

class MongoTopic < Topic
 
  attr_accessor :connections, :HEARTBEAT
  
  def initialize(name, db)
    super(name)
    
    @db = db
    
    if @db.collections_info(name + "_topic").has_next? and @db.collection(name + "_topic").capped?
      # Exists, and is capped, we're good
      @coll = @db.collection(name + "_topic")
    else
      # Doesn't exist, or isn't capped
      @db.drop_collection(name + "_topic")
      @coll = @db.create_collection(name + "_topic", :capped => true, :size => 20*(1024**2), :max => 100 )
    end
    
    @connections = Array.new
    @HEARTBEAT = "\0" #"<!-- OK -->\n"
    self.refresh
    
    ObjectSpace.define_finalizer(self, proc { @coll = nil; @connections=nil; @db=nil } )
  end
  
  def topics
    colls = @db.collection_names
    topics = Array.new
    colls.each do |coll|
      coll.match(/^(.*)_topic$/) do |topic|
        topics.push(topic[1])
      end
    end
    return topics
  end
  
  def empty?
    !!@connections.count
  end
  
  def format_message(message, event = false)
    message = "data: #{message}\n\n"
    message = "event: #{event}\n#{message}" if event
    return message
  end

  def notify(message)
    @connections.each { |out| out << self.format_message(message) }
  end
  
  def refresh(notify_connections = false)
    if notify_connections and !!@connections.count
      # They want us to tell the >= 1 connections
      new_history=self.read
      hist_diff=new_history-@history
      hist_diff.each do |entry|
        self.notify(entry)
      end
      @history=new_history
      @count = @history.count
    else
      # Speedy
      @history = self.read
      @count = @history.count
    end
  end
  
  def add(entry)
    doc = Hash.new
    doc['m'] = entry
    @coll.insert(doc)
    @last_updated = Time.now
    self.refresh(true)
  end
  
  def read(filter = nil, limit = nil)
    messages = Array.new
    
    if filter.nil?
      # All of it
      @coll.find.each { |row| 
        limit -= 1 unless limit.nil?
        messages.push(row["m"]) if row.has_key?("m")
        break if limit == 0
      }
    elsif filter.match(/^since:\d+$/)
      # All of it since the epoch date specified
      filter.match(/^since:(\d+)$/) do |epoch|
      time = Time.at(epoch[1].to_i)
      time_id = BSON::ObjectId.from_time(time,{ :unique => false })
      @coll.find({'_id' => {'$gt' => time_id}}).each { |row|
        limit -= 1 unless limit.nil?
        messages.push(row["m"]) if row.has_key?("m")
        break if limit == 0
      }
      end
    else
      # Filter
      # TODO: Intuitive filtering
      @coll.find(filter).each { |row| 
        limit -= 1 unless limit.nil?
        messages.push(row["m"]) if row.has_key?("m")
        break if limit == 0
      }
    end
    return messages
  end
end

class MongoChat < MongoTopic
  
  def initialize(room, db)
    super(room,db)
    
    @HEARTBEAT = "<!-- OK -->\n"
    
  end
  
  def format_message(message, from, style, user = nil)
    # TODO: wrap it in an HTML block, make sure it's clean
    # user = nil goes to all subscribers
  end
  
end

class SecureToken
  
  attr_accessor :key, :iv
  
  def initialize(key, iv)
    @key = key
    @iv = iv

    @aes = OpenSSL::Cipher.new("AES-256-CBC")
    @prng = Random.new
    
  end
  
  def build_token(payload)
 
    payload = [payload, Time.now.to_i, @prng.rand(10..9999)].join("\t")
    
    @aes.encrypt
    @aes.key = @key
    @aes.iv = @iv
    token = @aes.update(payload) + @aes.final
    return Base64.urlsafe_encode64(token)
  end
  
  # Returns false if the token is too old, else returns the payload
  def verify_token(token, time_tolerance_seconds = 60)
    payload, time, nonce = self.extract_token(token)
    return false if time.to_i+time_tolerance_seconds.to_i < Time.now.to_i
    return payload
  end
  
  def extract_token(token)
    
    token = Base64.urlsafe_decode64(token)
    
    @aes.decrypt
    @aes.key = key
    @aes.iv = iv
    clear_token = @aes.update(token) + @aes.final
    return clear_token.split("\t")
  end
end

=begin
require 'digest/sha2'
iv =  Digest::SHA2.new(256).digest("FBDfsdfrvyh8i67u5R^V$qc34x123e1w4rcq$Wtaw4twyj")
key = Digest::SHA2.new(256).digest("asasjhsdfFERt45y4hg3$&kjgfgf$Wsdcvbtymkhl8*r6t")

t = SecureToken.new(key,iv)

token = t.build_token("I would like a token please")

puts token
puts t.verify_token(token)

=begin
db = MongoClient.new("localhost", 27017).db("elasticbus")

m = MongoTopic.new('cooking',db)

puts m.connections

=begin
foods = Hash.new()
foods[:cake] = :lie
foods[:pie] =  :yum
foods[:pasta] = :ok
foods[:veggies] = :wtf
m.add(foods)
puts '---------------'
puts m.count

puts m.read == m.history
=end

