worker_processes 20
preload_app true
pid './unicorn.pid'
listen 8080
stderr_path './err.log'
stdout_path './out.log'
