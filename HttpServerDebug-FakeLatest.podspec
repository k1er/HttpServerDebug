Pod::Spec.new do |s|
  s.name         = "HttpServerDebug-FakeLatest"
  s.version      = "0.2.1.7"
  s.summary      = "HSD offers debug utilities (exploring file system, inspecting " \
                  "database, etc.) with the help of http server."
  s.description  = <<-DESC
                  HSD offers debug utilities (exploring file system, inspecting
                  database, etc.) with the help of http server. HSD will start
                  http server in your device, and you can connect to the server
                  through user agents in the local area network. 由于作者的pod版本未更新，
                  暂时新增一个pod的新版本，方便集成。
                   DESC

  s.homepage     = "https://github.com/rob2468/HttpServerDebug"
  s.screenshots  = "https://user-images.githubusercontent.com/1450652/44396867-ca139000-a570-11e8-9a5c-80da964159ba.gif", \
                  "https://user-images.githubusercontent.com/1450652/44396868-ca139000-a570-11e8-8a05-871de9efeb34.gif", \
                  "https://user-images.githubusercontent.com/1450652/44396869-ca139000-a570-11e8-9018-dc27634ebd9d.gif"
  s.license      = { :type => "MIT", :file => "LICENSE.txt" }
  s.author             = { "jam.chenjun" => "jam.chenjun@gmail.com" }
  s.social_media_url   = "https://weibo.com/rob2468"
  s.platform     = :ios, "8.0"
  s.source       = { :git => "https://github.com/k1er/HttpServerDebug.git", :commit => "50fee046f5546b901bd72bef39769cf9b076da11" }
  s.source_files  = "Classes/**/*.{h,m,c}"
  s.public_header_files = "Classes/**/{HSDDelegate,HSDHttpServerControlPannelController,HSDManager,HttpServerDebug}.h"
  s.resources = "Resources/HttpServerDebug.bundle"
  s.frameworks = "UIKit", "Foundation"
  s.requires_arc = true
  s.dependency "GCDWebServer", "~> 3.4"
  s.dependency "FMDB/FTS", "~> 2.6.2"
end
