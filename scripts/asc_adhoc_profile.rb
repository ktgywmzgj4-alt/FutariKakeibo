#!/usr/bin/env ruby
# frozen_string_literal: true

# App Store Connect の API で、Ad Hoc のプロビジョニングプロファイルを用意する。
#
# **ブラウザでのポータル操作を置き換えるためのもの。** 端末の登録も、証明書と
# 端末を束ねたプロファイルの作成も、TestFlight配信で使っているのと同じAPIキーでできる。
# GitHub Secrets に新しく何かを足す必要はない。
#
# 受け取るもの（すべて環境変数）:
#   ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH  … App Store Connect のAPIキー
#   BUNDLE_ID                                   … jp.aikawa.futarikakeibo
#   PROFILE_NAME                                … FutariKakeibo Ad Hoc
#   UDIDS                                       … カンマ区切り。空でもよい
#   OUTPUT_PATH                                 … 書き出す .mobileprovision
#
# **鍵とトークンは絶対に出力しない。** 失敗したときはAppleの返した本文を出すが、
# そこに鍵は入らない。

require 'base64'
require 'json'
require 'net/http'
require 'openssl'
require 'time'
require 'uri'

HOST = 'api.appstoreconnect.apple.com'

def env!(name)
  value = ENV[name].to_s
  abort "#{name} が渡されていません。" if value.empty?
  value
end

KEY_ID = env!('ASC_KEY_ID')
ISSUER_ID = env!('ASC_ISSUER_ID')
KEY_PATH = env!('ASC_KEY_PATH')
BUNDLE_ID = env!('BUNDLE_ID')
PROFILE_NAME = env!('PROFILE_NAME')
OUTPUT_PATH = env!('OUTPUT_PATH')
UDIDS = ENV['UDIDS'].to_s.split(/[,\s]+/).map(&:strip).reject(&:empty?)

def base64url(data)
  Base64.urlsafe_encode64(data).delete('=')
end

# JWSのES256は **r と s をそれぞれ32バイトに詰めて並べた64バイト**。
# OpenSSLが返すDERのままでは通らない。ここを間違えると401だけが返ってくる。
def jws_signature(key, signing_input)
  der = key.sign(OpenSSL::Digest.new('SHA256'), signing_input)
  numbers = OpenSSL::ASN1.decode(der).value
  parts = numbers.map { |n| n.value.to_s(2).b.rjust(32, "\x00".b) }
  parts.join
end

def token
  @token ||= begin
    key = OpenSSL::PKey::EC.new(File.read(KEY_PATH))
    now = Time.now.to_i
    header = { alg: 'ES256', kid: KEY_ID, typ: 'JWT' }
    payload = { iss: ISSUER_ID, iat: now, exp: now + 1200, aud: 'appstoreconnect-v1' }
    signing_input = "#{base64url(JSON.generate(header))}.#{base64url(JSON.generate(payload))}"
    "#{signing_input}.#{base64url(jws_signature(key, signing_input))}"
  end
end

def call(method, path, params: {}, body: nil)
  uri = URI::HTTPS.build(host: HOST, path: path)
  uri.query = URI.encode_www_form(params) unless params.empty?

  request = case method
            when :get then Net::HTTP::Get.new(uri)
            when :post then Net::HTTP::Post.new(uri)
            when :delete then Net::HTTP::Delete.new(uri)
            end
  request['Authorization'] = "Bearer #{token}"
  request['Content-Type'] = 'application/json'
  request.body = JSON.generate(body) if body

  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
  [response.code.to_i, response.body.to_s]
end

def data_of(code, body, what)
  abort "#{what} を取得できませんでした（HTTP #{code}）\n#{body}" unless (200..299).cover?(code)
  JSON.parse(body)['data']
end

# --- どのアプリか -------------------------------------------------------------

bundles = data_of(*call(:get, '/v1/bundleIds', params: { 'filter[identifier]' => BUNDLE_ID }),
                  'App ID')
bundle = bundles.find { |item| item.dig('attributes', 'identifier') == BUNDLE_ID }
abort "App ID #{BUNDLE_ID} が見つかりません。" if bundle.nil?
puts "App ID: #{BUNDLE_ID}"

# --- どの証明書で署名するか ---------------------------------------------------

all_certificates = data_of(*call(:get, '/v1/certificates', params: { 'limit' => 200 }), '証明書')
usable = all_certificates.select do |item|
  type = item.dig('attributes', 'certificateType')
  next false unless %w[DISTRIBUTION IOS_DISTRIBUTION].include?(type)
  expires = item.dig('attributes', 'expirationDate')
  expires.nil? || Time.parse(expires) > Time.now
end
abort '使える配布用の証明書がありません。' if usable.empty?
puts "証明書: #{usable.size}件（#{usable.map { |c| c.dig('attributes', 'certificateType') }.uniq.join(', ')}）"

# --- 端末を登録する -----------------------------------------------------------

UDIDS.each do |udid|
  code, body = call(:post, '/v1/devices', body: {
                      data: {
                        type: 'devices',
                        attributes: { name: "iPhone #{udid[0, 8]}", platform: 'IOS', udid: udid }
                      }
                    })
  case code
  when 200..299 then puts "端末を登録: #{udid[0, 8]}…"
  when 409 then puts "端末は登録済み: #{udid[0, 8]}…"
  else
    # 同じUDIDが既にあるだけなら続けてよい。それ以外は止める。
    abort "端末を登録できませんでした（HTTP #{code}）\n#{body}" unless body.include?('already exists')
    puts "端末は登録済み: #{udid[0, 8]}…"
  end
end

devices = data_of(*call(:get, '/v1/devices',
                        params: { 'filter[platform]' => 'IOS', 'limit' => 200 }), '端末の一覧')
enabled = devices.select { |item| item.dig('attributes', 'status') == 'ENABLED' }
abort '有効な端末が1台もありません。' if enabled.empty?
puts "プロファイルに入れる端末: #{enabled.size}台"

# --- プロファイルを作り直す ---------------------------------------------------

# プロファイルは後から端末を足せない。**同じ名前のものを消して作り直す。**
existing = data_of(*call(:get, '/v1/profiles',
                         params: { 'filter[name]' => PROFILE_NAME, 'limit' => 200 }),
                   'プロファイルの一覧')
existing.each do |item|
  code, body = call(:delete, "/v1/profiles/#{item['id']}")
  abort "古いプロファイルを消せませんでした（HTTP #{code}）\n#{body}" unless (200..299).cover?(code)
  puts "古いプロファイルを消した: #{PROFILE_NAME}"
end

code, body = call(:post, '/v1/profiles', body: {
                    data: {
                      type: 'profiles',
                      attributes: { name: PROFILE_NAME, profileType: 'IOS_APP_ADHOC' },
                      relationships: {
                        bundleId: { data: { type: 'bundleIds', id: bundle['id'] } },
                        certificates: {
                          data: usable.map { |c| { type: 'certificates', id: c['id'] } }
                        },
                        devices: {
                          data: enabled.map { |d| { type: 'devices', id: d['id'] } }
                        }
                      }
                    }
                  })
profile = data_of(code, body, 'プロファイルの作成')
content = profile.dig('attributes', 'profileContent')
abort "プロファイルの中身が返ってきませんでした。\n#{body}" if content.to_s.empty?

File.binwrite(OUTPUT_PATH, Base64.decode64(content))
puts "プロファイルを書き出した: #{PROFILE_NAME}（#{File.size(OUTPUT_PATH)} バイト）"
