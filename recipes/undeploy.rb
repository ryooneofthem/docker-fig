#docker_container 'ghost' do
#  action :remove
#end
execute "fig-service-down" do
    command "fig stop; fig rm --force"
end

