class User
  attr_accessor :screenname, :name, :token, :secret
  def initialize( screenname, attrs )
    @screenname = screenname
    @name = attrs['name']
    @token = attrs['token']
    @secret = attrs['secret']
  end

  def self.load screenname
    return nil if screenname.nil? || screenname == ""
    User.new( screenname, REDIS.hgetall( "user:#{screenname}" ))
  end
  
  def update
    self.update @screenname, @name, @token, @secret
  end

  def self.update screenname, name, token, secret
    key = "user:#{screenname}"
    REDIS.pipelined do
      REDIS.sadd "users", key

      REDIS.hmset key, "name", name
      REDIS.hmset key, "token", token
      REDIS.hmset key, "secret", secret
    end
  end
end

class Task
  class << self; attr_accessor :queue_name end
  @queue_name = self.name
  @@queues = {}

  # Queue methods

  def self.process_queues
    Task.queues.each do |queue_name,qclazz|
      Thread.start do
        qclazz.process( new_redis )
      end
    end

    sleep 60
  end

  def self.process( redis )
    while true
      puts "Waiting on #{@queue_name}"
      key = redis.blpop @queue_name
      task = queues[key[0]].load key[1]
      task.status = "processing"
      if task.process
        task.status = "loaded"
      end
      # task.notify_watchers
    end
  end

  def self.my_queue name
    self.queue_name = name
    Task.queues[queue_name] = self
  end

  def self.queues
    @@queues
  end

  def self.load key
    new(@queue_name,key)
  end

  # Task Methods

  def initialize(queue_name, key)
    @name = "#{queue_name}:#{key}"
    @key = key
    @attrs = REDIS.hgetall @name
  end

  def name
    @name
  end

  def key
    @key
  end

  def status= status
    REDIS.hmset name, "status", status
    @attrs['status'] = status
  end

  def status
    @attrs["status"]
  end
  
  def stale?
    status != "loaded" && status != "processing"
  end

  def self.ensure key
    task = load(key)

    if task.stale?
      if task.status != "queued"
        puts "Queueing the task:#{task.name} on #{queue_name}"
        REDIS.rpush queue_name, task.key
        task.status = "queued"
      end
    end
    task.status
  end

  def process
    puts "Processing #{@key}"
    true
  end
end

class TimelineTask < Task
  my_queue "timelines"
end

class FriendsTask < Task
  my_queue "friends"
end

class Word