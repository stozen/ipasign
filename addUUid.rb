require "spaceship"
require 'openssl'
require "mysql2"
require 'pathname'
require Pathname.new(File.dirname(__FILE__)).realpath.to_s + '/mysqlConfig'
require Pathname.new(File.dirname(__FILE__)).realpath.to_s + '/globalConfig'

#参考 https://github.com/fastlane/fastlane/blob/master/spaceship/docs/DeveloperPortal.md

apuid = ARGV[0].to_s;
username = ARGV[1].to_s;
password = ARGV[2].to_s;
uuid = ARGV[3].to_s;
bundleId = ARGV[4].to_s + '_' + apuid;


mobileprovision = '/sign.mobileprovision'

begin
    # 绝对路径
    cert_content = ARGV[2];
    p12_path = GlobalConfig::ROOT_KEY + '/' + ARGV[3].to_s;

    Spaceship::Portal.login(username, password)

    #添加 bundleId
    app = Spaceship::Portal.app.find(bundleId)
    if !app
        app = Spaceship::Portal.app.create!(bundle_id: bundleId, name: bundleId)
    end

    # 获取所有证书
    certificates = Spaceship::Portal.certificate.all

    if certificates.empty?
        raise "证书为空"
    end

    # 连接mysql
    client = Mysql2::Client.new(
        :host     => MysqlConfig::HOST,     # 主机
        :username => MysqlConfig::USER,      # 用户名
        :password => MysqlConfig::PASSWORD,    # 密码
        :database => MysqlConfig::DBNAME,      # 数据库
        :encoding => MysqlConfig::CHARSET      # 编码
    )

    #如果uuid不存在则添加uuid
    if !Spaceship::Portal.device.find_by_udid(uuid)
        Spaceship::Portal.device.create!(name:uuid, udid: uuid)

        #更新设备数量
        deviceLength = Spaceship::Portal.device.all.length
        client.query("update apple_developer set uuid_num = '#{deviceLength}'  where apuid = '#{apuid}'")

    end

    adHocAll = Spaceship.provisioning_profile.ad_hoc.all
    if adHocAll.empty?
        #ad_hoc 不存在

        #通过数据库 查询 证书id
        results = client.query("SELECT certificate_id FROM apple_developer_cer where apuid = '#{apuid}' limit 1")
        if !results.any?
            raise "证书 不存在, 请先上传或者创建证书"
        end


        certificateObj = results.first

        cert = Spaceship::Portal.certificate.production.find(certificateObj['certificate_id'])
        if !cert
            raise "证书#{certificateObj['id']} 不存在"
        end


        #创建 ad_hoc
        profile = Spaceship::Portal.provisioning_profile.ad_hoc.create!(bundle_id: bundleId, certificate: cert, name: username)
    end

    devices = Spaceship.device.all
    Spaceship.provisioning_profile.ad_hoc.all.each do |p|
        # 根据cert 证书创建
        #更新 ad_hoc
        p.devices = devices
        p.update!
    end

    # profile 写到对应的文件夹,以便更新
    c_time =  #{Time.now.strftime("%Y-%m-%d %H:%M:%S")}
    Spaceship.provisioning_profile.ad_hoc.all.each do |p|
        # 根据cert 证书创建

        certificateId = p.certificates.first.id
        mobileprovision =  '/applesign/' + username + '/' + certificateId + mobileprovision
        keyPath = GlobalConfig::ROOT_KEY +  '/applesign/' + username + '/' + certificateId
        system "mkdir -p #{keyPath}"
        system "chmod 777 #{keyPath}"

       # File.open(GlobalConfig::ROOT_KEY + mobileprovision,"a+") do |f|
       #   f.puts p.download
       # end

       File.write(GlobalConfig::ROOT_KEY + mobileprovision, p.download)

        # 保存uuid
        uUser = client.query("SELECT id FROM apple_developer_uuid WHERE uuid= '#{uuid}'")
        if uUser.any?
            client.query("update apple_developer_uuid set apuid = '#{apuid}' where uuid = '#{uuid}' ")
        else
            client.query("insert into apple_developer_uuid (apuid,uuid,c_time)values('#{apuid}', '#{uuid}', '#{c_time}')")
        end

        # 保存mobileprovision
        #  uUser = client.query("SELECT id FROM apple_developer_mobileprovision WHERE  build_id= '#{bundleId}' and certificate_id = '#{certificateId}'")
        mobileProvisionObj = client.query("SELECT id FROM apple_developer_mobileprovision WHERE certificate_id = '#{certificateId}'")

        if mobileProvisionObj.any?
            client.query("update apple_developer_mobileprovision set mobileprovision = '#{mobileprovision}' where certificate_id = '#{certificateId}' and build_id= '#{bundleId}'")
        else
            client.query("insert into apple_developer_mobileprovision (apuid, certificate_id, build_id, mobileprovision, c_time)values('#{apuid}', '#{certificateId}', '#{bundleId}', '#{mobileprovision}', '#{c_time}')")
        end
    end

rescue Exception  => e
     puts "Trace message: #{e}"
else
    puts "Success message: uuid添加成功"
ensure
     # 断开与服务器的连接
     client.close if client
end



