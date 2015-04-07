aws_instance_id         = node[:opsworks][:instance][:aws_instance_id]
layer                   = node[:opsworks][:instance][:layers].first
hostname                = node[:opsworks][:instance][:hostname]
private_ip              = node[:opsworks][:instance][:private_ip]
instances               = node[:opsworks][:layers].fetch(layer)[:instances].sort_by{|k,v| v[:booted_at] }
is_first_node           = instances.index{|i|i[0] == hostname} == 0

Chef::Log.debug("aws_instance_id: #{aws_instance_id}")
Chef::Log.debug("private_ip: #{private_ip}")
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

  ruby_block "get current hash" do
    only_if { layer == 'docker_web' and layer == deploy[:environment_variables][:layer]} 
    block do
      TMP_CURRENT_HASH = `cd #{deploy[:deploy_to]}/current/ && git rev-parse HEAD`
      ENV["TMP_CURRENT_HASH"] = TMP_CURRENT_HASH.strip 
      ENV["TMP_CURRENT_FILE"] = "#{TMP_CURRENT_HASH.strip}_app.tgz"
      puts "The last line is #{ENV['TMP_CURRENT_HASH']}"
      puts "The last file is #{ENV['TMP_CURRENT_FILE']}"
    end
    notifies :run, "execute[init s3 config]" 
  end
  
  execute "init s3 config" do
    only_if { layer == 'docker_web' and layer == deploy[:environment_variables][:layer]} 
    cwd "/root/"
    command "echo '[default]' > .s3cfg && echo access_key=$AWS_KEY_ID >> .s3cfg && echo secret_key=$AWS_SEC_KEY >> .s3cfg"
    environment OpsWorks::Escape.escape_double_quotes(deploy[:environment_variables])
    notifies :run, "execute[download app image]"
  end

  execute "download app image" do
    only_if { layer == 'docker_web' and layer == deploy[:environment_variables][:layer]} 
    cwd "/root/"
    command "s3cmd get s3://#{deploy[:environment_variables][:AWS_S3_BUCKET]}/images/$TMP_CURRENT_FILE ./$TMP_CURRENT_FILE --force || true"
    #icommand 'echo "s3cmd get s3://#{deploy[:environment_variables][:AWS_S3_BUCKET]}/images/$TMP_CURRENT_FILE ./$TMP_CURRENT_FILE --continue" > /tmp/xxx'
    action :nothing
    notifies :run, "execute[load app image]"
  end

  execute "load app image" do
    cwd "/root/"
    command "gunzip -c $TMP_CURRENT_FILE | docker load || true"
    action :nothing
    notifies :run, "execute[build app image]"
    notifies :run, "execute[check app image]"
  end

  execute "build app image" do
    not_if "docker images |grep local/app"
    cwd "#{deploy[:deploy_to]}/current/"
    command "docker build -t local/app ."
    action :nothing
  end
  
  execute "check app image" do
    only_if "docker images |grep local/app"
    cwd "#{deploy[:deploy_to]}/current/"
    command "docker images |grep local/app"
    action :nothing
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
    action :nothing
    subscribes :run, "execute[build app image]"
    subscribes :run, "execute[check app image]"
end

execute "fig-run-db" do
    only_if { layer == 'docker_db'} 
    cwd "#{fig_work_dir}"
    command "fig up -d db"
end
