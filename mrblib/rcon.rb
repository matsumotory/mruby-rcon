class Rcon
  include Cgroup

  def initialize c
    @class_config = c
    @user = c[:user] || ENV["USER"]
    raise "invalid user" if @user.nil? && @class_config[:pids].nil?
    @cgroup_name = c[:resource][:group] ? c[:resource][:group] : "mruby-virtual"
    @cgroup_root = c[:resource][:root] ? c[:resource][:root] : "/cgroup"
  end

  def setup_mem_eventfd type, val, e
    # TODO: implement memory method using libcgroup API
    fd = 0
    c = Cgroup::MEMORY.new @cgroup_name
    c.modify
    if type == :oom
      fd = File.open("#{@cgroup_root}/memory/#{@cgroup_name}/memory.oom_control", "r").fileno
      c.cgroup_event_control = "#{e.fd} #{fd}"
    elsif type == :usage && val
      fd = File.open("#{@cgroup_root}/memory/#{@cgroup_name}/memory.usage_in_bytes", "r").fileno
      c.cgroup_event_control = "#{e.fd} #{fd} #{val}"
    else
      raise "invalid mem event type or resource config. :oom or :usage"
    end
    c.modify
    fd
  end

  # type :oom or :usage
  def run_with_mem_eventfd type = :oom, val = nil, &b
    e = Eventfd.new 0, 0
    run_on_fork
    fd = setup_mem_eventfd type, val, e
    e.event_read &b
    e.close
    IO.new(fd).close
  end

  def run_with_mem_eventfd_loop type = :oom, val = nil, &b
    e = Eventfd.new 0, 0
    run_on_fork
    fd = setup_mem_eventfd type, val, e
    SignalThread.trap(:INT) { |signo|
      e.close
      IO.new(fd).close
      exit 1
    }
    SignalThread.trap(:TERM) { |signo|
      e.close
      IO.new(fd).close
      exit 1
    }
    loop { e.event_read &b }
  end

  def run_on_fork
    pid = Process.fork() do
      run
    end
  end

  def exec_cmd user, cmd
    ret = system "sudo -u #{user} #{cmd}"
    ret
  end

  def run
    setup_cgroup @class_config[:resource]
    if @class_config[:pids].nil?
      exec_cmd @user, @class_config[:command]
      Cgroup::CPU.new(@cgroup_name).delete
      Cgroup::BLKIO.new(@cgroup_name).delete
      Cgroup::MEMORY.new(@cgroup_name).delete
    end
  end

  def setup_cgroup_cpu config
    c = Cgroup::CPU.new @cgroup_name
    c.cfs_quota_us = config[:cpu_quota]
    c.create
    if @class_config[:pids].nil?
      c.attach
    else
      @class_config[:pids].each do |pid|
        c.attach pid
      end
    end
  end

  def setup_cgroup_blkio config
    io = Cgroup::BLKIO.new @cgroup_name
    io.throttle_read_bps_device = "#{config[:blk_dvnd]} #{config[:blk_rbps]}" if config[:blk_rbps]
    io.throttle_write_bps_device = "#{config[:blk_dvnd]} #{config[:blk_wbps]}" if config[:blk_wbps]
    io.create
    if @class_config[:pids].nil?
      io.attach
    else
      @class_config[:pids].each do |pid|
        io.attach pid
      end
    end
  end

  def setup_cgroup_mem config
    mem = Cgroup::MEMORY.new @cgroup_name
    mem.limit_in_bytes = config[:mem]
    unless config[:oom].nil?
      mem.oom_control = (config[:oom] == true) ? false : true
    end
    mem.create
    if @class_config[:pids].nil?
      mem.attach
    else
      @class_config[:pids].each do |pid|
        mem.attach pid
      end
    end
  end

  def setup_cgroup config
    # TODO: implement blkio and mem
    setup_cgroup_cpu config if config[:cpu_quota]
    setup_cgroup_blkio config if config[:blk_dvnd] && config[:blk_rbps] || config[:blk_wbps]
    setup_cgroup_mem config if config[:mem]
    if @class_config[:pids].nil?
      SignalThread.trap(:INT) { |signo|
        Cgroup::CPU.new(@cgroup_name).delete
        Cgroup::BLKIO.new(@cgroup_name).delete
        Cgroup::MEMORY.new(@cgroup_name).delete
        exit 1
      }
      SignalThread.trap(:TERM) { |signo|
        Cgroup::CPU.new(@cgroup_name).delete
        Cgroup::BLKIO.new(@cgroup_name).delete
        Cgroup::MEMORY.new(@cgroup_name).delete
        exit 1
      }
    end
  end
end
