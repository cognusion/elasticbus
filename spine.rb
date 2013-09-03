#!/usr/bin/env ruby

require 'mongo'
require 'bson'
require 'json'

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

  def add(entry, options = nil)
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
    @HEARTBEAT = "\0"
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
  
  def refresh(options = { :notify_connections => false })
    
    # Mangle options to pass to read
    read_options = options
    read_options.delete(:notify_connections)
    
    
    if options[:notify_connections] and !!@connections.count
      # They want us to tell the >= 1 connections
      new_history=self.read(read_options)
      hist_diff=new_history-@history
      hist_diff.each do |entry|
        self.notify(entry) #  Notify needs to be user aware, if applicable
      end
      @history=new_history
      @count = @history.count
    else
      # Speedy
      @history = self.read(read_options)
      @count = @history.count
    end
  end
  
  def add(entry, options = {})
    doc = Hash.new
    refresh_options = options
    refresh_options[:notify_connections => true]
    if(options.has_key?(:raw) and options[:raw] == true) 
      doc = entry
    else
      doc['m'] = entry
    end
    @coll.insert(doc)
    @last_updated = Time.now
    self.refresh(refresh_options)
  end
  
  def read(options = {})
    messages = Array.new
    
    filter = options[:filter] || nil
    limit  = options[:limit]  || nil
    raw    = options[:raw]    || nil
    
    if filter.nil?
      # All of it
      
      @coll.find.each { |row| 
        limit -= 1 unless limit.nil?
        if raw
          messages.push(row)
        else 
          messages.push(row["m"]) if row.has_key?("m")
        end
        break if limit == 0
      }
    elsif filter.match(/^since:\d+$/)
      # All of it since the epoch date specified
      
      filter.match(/^since:(\d+)$/) do |epoch|
      time = Time.at(epoch[1].to_i)
      time_id = BSON::ObjectId.from_time(time,{ :unique => false })
      @coll.find({'_id' => {'$gt' => time_id}}).each { |row|
        limit -= 1 unless limit.nil?
        if raw
          messages.push(row)
        else 
          messages.push(row["m"]) if row.has_key?("m")
        end
        break if limit == 0
      }
      end
    else
      # Filter
      
      # TODO: Intuitive filtering
      @coll.find(filter).each { |row| 
        limit -= 1 unless limit.nil?
        if raw
          messages.push(row)
        else 
          messages.push(row["m"]) if row.has_key?("m")
        end
        break if limit == 0
      }
    end
    return messages
  end
end

class MongoChat < MongoTopic

  def initialize(room, db, key, iv)
    super(room,db)
    
    @key = key
    @iv = iv
    @HEARTBEAT = "<!-- OK -->\n"
    
  end
  
  def user_from_connection(connection)
    cookie = connection.instance_variable_get(:@app).request.cookies['session']
    t = SecureToken.new(@key,@iv)
    t.from_token(cookie,true)
    return t.payload 
  end
  
  def notify(message)
    
    @connections.each do |out|
      if(!message.has_key?(:user) or message[:user].nil? or message[:user] == :all)
        # Broadcast
        out << self.format_message(message)
      else 
        # Unicast
        this_user = self.user_from_connection(out)
        out << self.format_message(message) if this_user == message[:user]   
      end
    end
  end
  
  def format_message(entry)
    # Assumes all variables properly 
    # Sanitized before passing!!!
    message = entry[:message]
    from    = entry[:from]
    style   = entry[:style]
    user    = entry[:user] if entry.has_key?(:user) || nil
    
    # user = nil goes to all subscribers
    prefix = "<p><b>#{from} #{style}"
    prefix += " Everyone</b>" if user.nil?
    prefix += " #{user}" unless user.nil?
      
    suffix = "</p>"

    return prefix + message + suffix
  end
  
end



=begin
require 'digest/sha2'
iv =  Digest::SHA2.new(256).digest("FBDfsdfrvyh8i67u5R^V$qc34x123e1w4rcq$Wtaw4twyj")
key = Digest::SHA2.new(256).digest("asasjhsdfFERt45y4hg3$&kjgfgf$Wsdcvbtymkhl8*r6t")

t = SecureToken.new(key,iv)

t.payload = "I would like a token please"

puts t.to_s

token = t.to_e(true)

x = SecureToken.new(key,iv)
x.from_token(token,true)
puts x.to_s()
puts x.verify("I would like a token please")

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

