execute "fig-install" do
    not_if { ::File.exists?("/usr/local/bin/fig")}
    command "curl -L https://github.com/docker/fig/releases/download/1.0.1/fig-`uname -s`-`uname -m` > /usr/local/bin/fig; chmod +x /usr/local/bin/fig"
end

execute "dockergen-install" do
    not_if { ::File.exists?("/usr/local/bin/docker-gen")}
    command "curl -L https://github.com/jwilder/docker-gen/releases/download/0.3.4/docker-gen-linux-amd64-0.3.4.tar.gz | tar xz -C /usr/local/bin"
end

execute "restart-autofs" do
    command "service autofs restart"
end
