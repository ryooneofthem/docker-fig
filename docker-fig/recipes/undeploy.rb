#docker_container 'ghost' do
#  action :remove
#end
execute "fig-service-down" do
    command "cd /root/docker; fig stop; fig rm --force; rm -rf /root/docker"
end

