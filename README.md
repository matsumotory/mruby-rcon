# rcon

rcontroler is a lightweight virtualization tool for linux processes.



## build rcon
```
rake
```

and create `rcon` binary into current directory.

## example
```ruby
# httpd.rb
Rcon.new({

  :command => "/usr/sbin/httpd -X",

  :resource => {

    # cgroup name
    :group => "httpd",

    # cgroup root path
    # centos "/cgroup" by default
    # ubuntu "/sys/fs/cgroup"
    :root => "/cgroup"

    # CPU [msec] exc: 30000 -> 30%
    :cpu_quota => 30000,

    # IO [Bytes/sec]
    :blk_dvnd => "202:0",
    :blk_rbps => 10485760,
    :blk_wbps => 10485760,

    # Memory [Bytes]
    :mem => 512 * 1024 * 1024,
    :oom => true,

  },

}).run
# callback memory limit event (default :oom)
# }).run_with_mem_eventfd do |ret|
#   puts "OOM KILLER!!! > #{ret}"
# end

# callback memory limit event for oom
# }).run_with_mem_eventfd(:oom) do |ret|
#   puts "OOM KILLER!!! > #{ret}"
# end

# callback memory limit event for usage(4MByte)
# }).run_with_mem_eventfd(:usage, 4 * 1024 * 1024) do |ret|
#   puts "Usage Up or Down to threadshould !!! > #{ret}"
# end

```

## run
```
sudo ./rcon httpd.rb
```

### auto memory expansion example
```ruby
Virtualing.new({
#(snip)
  :resource => {
    #(snip)
    :oom => false,
  },
#(snip)
}).run_with_mem_eventfd_loop do |ret|
  puts "OOM KILLER!!! current memory: #{mem}"
  sleep 2
  c = Virtualing::MEMORY.new group
  mem = mem * 2
  c.limit_in_bytes = mem
  c.modify
  puts "current memory expand to #{mem}"
end
```

## License
under the MIT License:
- see LICENSE file

