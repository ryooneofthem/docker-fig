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
  
  #execute "pre-run-jmeter" do
  #  only_if { layer == 'docker_jmeter' } 
  #  cwd "/srv/www/docker/current/"
  #  command "dockerize -template #{deploy[:deploy_to]}/current/jmeter/jmeter-senario1.jmx.tmpl:#{deploy[:deploy_to]}/current/jmeter/jmeter-senario1.jmx bash"
  #  environment OpsWorks::Escape.escape_double_quotes(deploy[:environment_variables])
  #  returns 2
  #end
  
  execute "pre-run-fig" do
    only_if { deploy[:environment_variables][:layer] == 'docker'} 
    cwd "#{deploy[:deploy_to]}/current/"
    command "cp fig.yml fig.yml.tmpl && docker-gen -only-published fig.yml.tmpl fig.yml" 
    environment OpsWorks::Escape.escape_double_quotes(deploy[:environment_variables])
  end

  node.set["TMP_CURRENT_HASH"] = ""
  node.set["TMP_CURRENT_FILE"] = ""
  b = ruby_block "get current hash" do
    block do
      TMP_CURRENT_HASH = `cd #{deploy[:deploy_to]}/current/ && git rev-parse HEAD`
      node.override["TMP_CURRENT_HASH"] = TMP_CURRENT_HASH.strip 
      node.override["TMP_CURRENT_FILE"] = "#{node[:TMP_CURRENT_HASH]}_app.tgz"
      puts "The last line is #{node[:TMP_CURRENT_HASH]}"
    end
  end
  b.run_action(:create)
  
  execute "init s3 config" do
    only_if { layer == 'docker_web' and layer == deploy[:environment_variables][:layer]} 
    cwd "/root/"
    command "echo '[default]' > .s3cfg && echo access_key=$AWS_KEY_ID >> .s3cfg && echo secret_key=$AWS_SEC_KEY >> .s3cfg"
    environment OpsWorks::Escape.escape_double_quotes(deploy[:environment_variables])
  end

  execute "download app image" do
    only_if { layer == 'docker_web' and layer == deploy[:environment_variables][:layer] and !node[:TMP_CURRENT_HASH].blank?} 
    cwd "/root/"
    command "s3cmd get s3://#{deploy[:environment_variables][:AWS_S3_BUCKET]}/images/$TMP_CURRENT_FILE ./$TMP_CURRENT_FILE --continue"
    environment "TMP_CURRENT_FILE" => "#{node[:TMP_CURRENT_FILE]}"
  end

  execute "load app image" do
    only_if { layer == 'docker_web' and layer == deploy[:environment_variables][:layer]} 
    cwd "/root/"
    command "gunzip -c $TMP_CURRENT_FILE | docker load"
    environment "TMP_CURRENT_FILE" => "#{node[:TMP_CURRENT_FILE]}"
  end
end

include_recipe "docker-fig::create_env_file"

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

#execute "fig-build-fluentd" do
#    cwd "#{fig_work_dir}"
#    command "fig build fluentd"
#end

#execute "fig-run-fluentd" do
#    cwd "#{fig_work_dir}"
#    command "fig up -d logspout"
#end

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
