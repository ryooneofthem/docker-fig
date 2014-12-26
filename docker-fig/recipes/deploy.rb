aws_instance_id         = node[:opsworks][:instance][:aws_instance_id]
layer                   = node[:opsworks][:instance][:layers].first
hostname                = node[:opsworks][:instance][:hostname]
instances               = node[:opsworks][:layers].fetch(layer)[:instances].sort_by{|k,v| v[:booted_at] }
is_first_node           = instances.index{|i|i[0] == hostname} == 0

Chef::Log.debug("aws_instance_id: #{aws_instance_id}")
Chef::Log.debug("layer: #{layer}")
Chef::Log.debug("instances: #{instances.map{|i| i[0] }.join(', ')}")
Chef::Log.debug("is_first_node: #{is_first_node}")
Chef::Log.debug("hostname: #{hostname}")

node[:deploy].each do |application, deploy|
  if 'docker' != deploy[:environment_variables][:layer] and node[:opsworks][:instance][:layers].first != deploy[:environment_variables][:layer]
    Chef::Log.debug("Skipping deploy::docker application #{application} as it is not deployed to this layer")
    next
  end

  opsworks_deploy_dir do
    user deploy[:user]
    group deploy[:group]
    path deploy[:deploy_to]
  end

  opsworks_deploy do
    app application
    deploy_data deploy
  end

  #link "/srv/www/docker/current/app/cross-platform" do
  #  only_if { deploy[:environment_variables][:layer] == 'web'} 
  #  to "#{deploy[:deploy_to]}/current/"
  #end

end

directory "/srv/www/docker/current/app/" do
  #user deploy[:user]
  #group deploy[:group]
  mode '0755'
  action :create
end

link "/srv/www/docker/current/app/cross-platform" do
    to "/srv/www/web/current/"
end

execute "fig-build" do
    cwd "/srv/www/docker/current/"
    command "fig build"
end

execute "fig-run-web" do
    only_if { layer == 'web'} 
    cwd "/srv/www/docker/current/"
    command "fig up web -d"
end
execute "fig-run-db" do
    only_if { layer == 'db'} 
    cwd "/srv/www/docker/current/"
    command "fig up db -d"
end
