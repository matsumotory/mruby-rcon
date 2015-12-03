class Rcon
  include Cgroup

  def initialize c
    @config = c
    @user = c[:user] || ENV["USER"]
    raise "invalid user" if @user.nil?
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
    Signal.trap(:INT) { |signo|
      e.close
      IO.new(fd).close
      exit 1
    }
    Signal.trap(:TERM) { |signo|
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
    setup_cgroup @config[:resource]
    exec_cmd @user, @config[:command] if @config[:pids].nil?
    Cgroup::CPU.new(@cgroup_name).delete
    Cgroup::BLKIO.new(@cgroup_name).delete
    Cgroup::MEMORY.new(@cgroup_name).delete
  end

  def setup_cgroup_cpu config
    c = Cgroup::CPU.new @cgroup_name
    c.cfs_quota_us = config[:cpu_quota]
    c.create
    if config[:pids].nil?
      c.attach
    else
      config[:pids].each do |pid|
        c.attach pid
      end
    end
  end

  def setup_cgroup_blkio config
    io = Cgroup::BLKIO.new @cgroup_name
    io.throttle_read_bps_device = "#{config[:blk_dvnd]} #{config[:blk_rbps]}" if config[:blk_rbps]
    io.throttle_write_bps_device = "#{config[:blk_dvnd]} #{config[:blk_wbps]}" if config[:blk_wbps]
    io.create
    if config[:pids].nil?
      io.attach
    else
      config[:pids].each do |pid|
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
    if config[:pids].nil?
      mem.attach
    else
      config[:pids].each do |pid|
        mem.attach pid
      end
    end
  end

  def setup_cgroup config
    # TODO: implement blkio and mem
    setup_cgroup_cpu config if config[:cpu_quota]
    setup_cgroup_blkio config if config[:blk_dvnd] && config[:blk_rbps] || config[:blk_wbps]
    setup_cgroup_mem config if config[:mem]
    Signal.trap(:INT) { |signo|
      Cgroup::CPU.new(@cgroup_name).delete
      Cgroup::BLKIO.new(@cgroup_name).delete
      Cgroup::MEMORY.new(@cgroup_name).delete
      exit 1
    }
    Signal.trap(:TERM) { |signo|
      Cgroup::CPU.new(@cgroup_name).delete
      Cgroup::BLKIO.new(@cgroup_name).delete
      Cgroup::MEMORY.new(@cgroup_name).delete
      exit 1
    }
  end
end
