include_recipe "docker-fig::create_env_file"

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
  execute "pre-run-jmeter" do
    only_if { layer == 'docker_jmeter' } 
    cwd "/srv/www/docker/current/"
    command "dockerize -template #{deploy[:deploy_to]}/current/jmeter/jmeter-senario1.jmx.tmpl:#{deploy[:deploy_to]}/current/jmeter/jmeter-senario1.jmx bash"
    environment OpsWorks::Escape.escape_double_quotes(deploy[:environment_variables])
    returns 2
  end

end

fig_origin_dir = '/srv/www/docker/current'
fig_work_dir = '/root/docker'

execute "init-docker-fig-dir" do
    cwd "#{fig_origin_dir}"
    command "mkdir -p #{fig_work_dir}; cp -a #{fig_origin_dir}/* #{fig_work_dir}/"
end

directory "#{fig_work_dir}/app/" do
  only_if { layer == 'docker_web'} 
  #user deploy[:user]
  #group deploy[:group]
  mode '0755'
  action :create
end

execute "mount-app-dir" do
    only_if { layer == 'docker_web'}
    cwd "#{fig_work_dir}/app/"
    command "mkdir cross-platform; cp -a /srv/www/web/current/* cross-platform/"
end

execute "fig-build-app" do
    cwd "#{fig_work_dir}"
    only_if { layer == 'docker_web'} 
    command "fig build app"
end

execute "fig-build-web" do
    cwd "#{fig_work_dir}"
    only_if { layer == 'docker_web'} 
    command "fig build web"
end

execute "fig-build-db" do
    cwd "#{fig_work_dir}"
    only_if { layer == 'docker_db'} 
    command "fig build db"
end

execute "fig-run-web" do
    only_if { layer == 'docker_web'} 
    cwd "#{fig_work_dir}"
    command "fig up -d app web"
end

execute "fig-run-db" do
    only_if { layer == 'docker_db'} 
    cwd "#{fig_work_dir}"
    command "fig up -d db"
end

execute "fig-run-jmeter" do
    only_if { layer == 'docker_jmeter'} 
    cwd "#{fig_work_dir}"
    command "fig up -d jmeter"
end
