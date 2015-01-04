execute "fig-install" do
    not_if { ::File.exists?("/usr/local/bin/fig")}
    command "curl -L https://github.com/docker/fig/releases/download/1.0.1/fig-`uname -s`-`uname -m` > /usr/local/bin/fig; chmod +x /usr/local/bin/fig"
end

execute "dockerize-install" do
    not_if { ::File.exists?("/usr/local/bin/dockerize")}
    command "curl -L https://github.com/jwilder/dockerize/releases/download/v0.0.1/dockerize-linux-amd64-v0.0.1.tar.gz | tar xz -C /usr/local/bin"
end

execute "unlimit-setup" do
    command "ulimit -n 65536"
    notifies :restart, 'service[docker]', :immediately
end

service 'docker' do
  supports :status => true, :restart => true, :reload => true
  action [:start, :enable]
end
