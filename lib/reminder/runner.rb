class ReminderRunner
  attr_accessor :scheduler, :robot, :reminders, :redis
  def initialize()
    @reminders = []
    @started = false
  end

  def start(robot, redis)
    @robot = robot
    @redis = redis
    return if @started
    @started = true
    @reminder_count = redis.llen("reminders")
    @scheduler = Rufus::Scheduler.start_new
    @redis.lrange('reminders', 0, -1).each_with_index do |task, index|
      if task.nil? || task == ''
        @reminders[index] = nil
      else
        @reminders << ReminderTask.load(index, task)
      end
    end
    @reminders.each do |task|
      task.start_job(self) unless task.nil?
    end

  end

  def add(response)
    task = ReminderTask.from_message(@reminder_count, response.match_data, response.message.source)
    @redis.rpush("reminders", task.dump)
    @reminders << task
    task.start_job(self)
    response.reply("Task #{task.index} added, next run at #{task.job.next_time.strftime('%Y-%m-%d %H:%M:%S')}")
    @reminder_count += 1
  end

  def done(response)
    @reminders[response.match_data[1].to_i].stop_repeat
  end
  
  def delete(response)
    index = response.match_data[1].to_i
    if @reminders[index].nil?
      response.reply("Task #{index} does not exist")
    elsif index != @reminders[index].index
      response.reply("Task #{index} is broken (bot internal error)")
    else
      kill(index)
      response.reply("Task #{index} deleted")
    end
  end

  def list(response)
    reminders = @reminders.reject{|r| r.nil? }
    if reminders.empty?
      response.reply "no active reminders"
    else
      response.reply(reminders.map(&:to_s).join("\n"))
    end
  end

  def clear
    @redis.ltrim("reminders", 0, 0)
    @reminders.reject{|task| task.nil? }.map(&:die)
    @reminders = []
    @reminder_count = 0
  end

  def kill(index)
    @reminders[index].die
    @reminders[index] = nil
    @redis.lset("reminders", index, nil)
    index
  end

end
