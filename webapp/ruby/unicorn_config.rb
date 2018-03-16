worker_processes 20
preload_app true
pid './unicorn.pid'
listen "#{`pwd`.chomp}/unicorn.sock"
stderr_path './err.log'
stdout_path './out.log'
