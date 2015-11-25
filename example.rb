Rcon.new({

  :user => "daemon",
  :command => "./loop.sh",

  :resource => {

    :group => "example-loop",

    # CPU [msec] exc: 30000 -> 30%
    :cpu_quota => 30000,

    # IO [Bytes/sec]
    :blk_dvnd => "202:0",
    :blk_rbps => 10485760,
    :blk_wbps => 10485760,

    # Memory [Bytes]
    :mem => 512 * 1024 * 1024,
  },

}).run

