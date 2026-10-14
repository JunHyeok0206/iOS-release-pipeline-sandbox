# Timespread 와 같은 방식의 CocoaPods 의존성. deploy.yml 의 캐시(Pods/) 검증용. tuist generate 뒤에 pod install.
source 'https://cdn.cocoapods.org/'
install! 'cocoapods', warn_for_unused_master_specs_repo: false
platform :ios, '17.0'
use_frameworks!

project 'TestApp.xcodeproj'
workspace 'TestApp'

target 'TestApp' do
  pod 'Toast-Swift', '5.1.1'
end
