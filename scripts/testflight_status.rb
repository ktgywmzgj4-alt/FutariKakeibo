#!/usr/bin/env ruby
# frozen_string_literal: true

# TestFlightへ送ったビルドが、App Store Connect 側で処理を終えて
# **内部テスターに配られたか**を確かめる。
#
# `altool` の `UPLOAD SUCCEEDED` は「Appleが受け取った」までしか言わない。
# そのあと10〜30分の処理があり、そこで落ちることもある。
# 以前、処理中のあいだに利用者から「配信されていない」と見えていた（2026-10-13）。
#
# **AIは鍵の中身を見ない約束なので、確かめるのはGitHub Actionsのジョブの中で行う。**
# AIはこのジョブの結果（ログ・注記・まとめ）だけを読む。
#
# 受け取るもの（すべて環境変数）:
#   ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH  … App Store Connect のAPIキー
#   BUNDLE_ID                                   … jp.aikawa.futarikakeibo
#   BUILD_NUMBER                                … CFBundleVersion（例 2026.1014.0930）
#
# 終わり方:
#   0 … 内部テスターに配られた。または、待ちきれず最後の状態を注記して終えた
#   1 … 処理に失敗した、輸出コンプライアンスの回答が要る、または問い合わせの形が誤っている
#
# **鍵とトークンは絶対に出力しない。** 失敗したときはAppleの返した本文を出すが、
# そこに鍵は入らない。
#
# `ruby scripts/testflight_status.rb --self-test` で、使い捨ての鍵を作って
# 署名と判定だけを確かめられる（App Store Connect には何も問い合わせない）。

require 'base64'
require 'json'
require 'net/http'
require 'openssl'
require 'time'
require 'uri'

HOST = 'api.appstoreconnect.apple.com'

# 処理は普通10〜30分。これを過ぎたら、最後に見えた状態を書いて終える。
DEADLINE_SECONDS = 30 * 60
POLL_SECONDS = 30

# トークンの有効期限は最長20分。待つあいだに切れるので、15分で作り直す。
TOKEN_LIFETIME_SECONDS = 20 * 60
TOKEN_REFRESH_SECONDS = 15 * 60

def env!(name)
  value = ENV[name].to_s
  abort "#{name} が渡されていません。" if value.empty?
  value
end

def base64url(data)
  Base64.urlsafe_encode64(data).delete('=')
end

# JWSのES256は **r と s をそれぞれ32バイトに詰めて並べた64バイト**。
# OpenSSLが返すDERのままでは通らない。ここを間違えると401だけが返ってくる。
# （`scripts/asc_adhoc_profile.rb` と同じ。あちらは本物の鍵で通っている）
def jws_signature(key, signing_input)
  der = key.sign(OpenSSL::Digest.new('SHA256'), signing_input)
  numbers = OpenSSL::ASN1.decode(der).value
  parts = numbers.map { |n| n.value.to_s(2).b.rjust(32, "\x00".b) }
  parts.join
end

def make_token(key, key_id:, issuer_id:, now:)
  header = { alg: 'ES256', kid: key_id, typ: 'JWT' }
  payload = { iss: issuer_id, iat: now, exp: now + TOKEN_LIFETIME_SECONDS, aud: 'appstoreconnect-v1' }
  signing_input = "#{base64url(JSON.generate(header))}.#{base64url(JSON.generate(payload))}"
  "#{signing_input}.#{base64url(jws_signature(key, signing_input))}"
end

# 1回分の答えを、次にどうするかの判断に変える。
#
# 返すもの: [判定, 説明]
#   :ready        … 内部テスターに配られた（ここで終える）
#   :failed       … 処理に失敗した。テスターには届かない
#   :needs_action … 人の操作が要る（輸出コンプライアンス）
#   :waiting      … まだ途中。もう一度見る
#   :not_found    … まだ一覧に出ていない（送った直後は数分出ない）。もう一度見る
def classify(response)
  build = (response['data'] || []).first
  return [:not_found, 'まだビルドの一覧に出ていない'] if build.nil?

  state = build.dig('attributes', 'processingState')
  detail = (response['included'] || []).find { |item| item['type'] == 'buildBetaDetails' }
  internal = detail&.dig('attributes', 'internalBuildState')

  case state
  when 'FAILED', 'INVALID'
    [:failed, "App Store Connect の処理が #{state} で終わった"]
  when 'VALID'
    case internal
    when 'IN_BETA_TESTING'
      [:ready, '内部テスターに配られた']
    when 'MISSING_EXPORT_COMPLIANCE'
      [:needs_action, '輸出コンプライアンスの回答待ち（App Store Connect で答える必要がある）']
    when 'PROCESSING_EXCEPTION', 'EXPIRED'
      [:failed, "内部テストの状態が #{internal}"]
    when 'READY_FOR_BETA_TESTING'
      [:waiting, '処理は済んだが、まだ内部テストのグループに入っていない']
    else
      [:waiting, "処理は済み、内部テストの状態は #{internal || '未取得'}"]
    end
  else
    [:waiting, "処理中（#{state || '状態不明'}）"]
  end
end

def version_of(response)
  version = (response['included'] || []).find { |item| item['type'] == 'preReleaseVersions' }
  version&.dig('attributes', 'version')
end

def internal_state_of(response)
  detail = (response['included'] || []).find { |item| item['type'] == 'buildBetaDetails' }
  detail&.dig('attributes', 'internalBuildState')
end

def processing_state_of(response)
  (response['data'] || []).first&.dig('attributes', 'processingState')
end

# GitHub Actions の注記。ジョブの画面と、check-runs の注記APIの両方に出る。
def annotate(level, message)
  puts "::#{level} title=TestFlight::#{message}"
end

def write_summary(lines)
  path = ENV['GITHUB_STEP_SUMMARY'].to_s
  return if path.empty?

  File.open(path, 'a') { |file| file.puts(lines) }
end

# --- 配り方の診断（読むだけ） -------------------------------------------------
#
# 「新しいビルドが来ても自動で入れ替わらない」という報告（2026-10-15）を調べるためのもの。
# Apple側で確かめられるのは、内部テストのグループに「ビルドを自動で配る」設定が
# 入っているかと、最近のビルドがそれぞれどの状態にあるかまで。
# 端末側の自動アップデート（TestFlightアプリの設定と、iOSが入れ替える時機）は見えない。
#
# **リポジトリは公開なので、ログにはテスターの名前やメールも、グループ名も出さない。**

# 内部テストのグループの一覧から、気をつけることを挙げる。
def distribution_findings(groups)
  internal = groups.select { |group| group.dig('attributes', 'isInternalGroup') }
  return ['内部テストのグループが1つも無い。ビルドを受け取れるテスターがいない'] if internal.empty?

  if internal.none? { |group| group.dig('attributes', 'hasAccessToAllBuilds') }
    return ['内部テストのグループに「ビルドを自動で配る」設定が無い。' \
            '新しいビルドは App Store Connect で手で足さないとテスターに出ない']
  end

  []
end

# 最近のビルドを、表の行にする。
def build_rows(response)
  included = (response['included'] || []).to_h { |item| [[item['type'], item['id']], item] }
  (response['data'] || []).map do |build|
    version_ref = build.dig('relationships', 'preReleaseVersion', 'data')
    detail_ref = build.dig('relationships', 'buildBetaDetail', 'data')
    version = version_ref && included[[version_ref['type'], version_ref['id']]]&.dig('attributes', 'version')
    internal = detail_ref && included[[detail_ref['type'], detail_ref['id']]]&.dig('attributes', 'internalBuildState')
    attributes = build['attributes'] || {}
    {
      version: version || '-',
      build: attributes['version'] || '-',
      processing: attributes['processingState'] || '-',
      internal: internal || '-',
      expiry: attributes['expired'] ? '期限切れ' : '有効',
      uploaded: attributes['uploadedDate'] || '-'
    }
  end
end

# 読むだけ。ここで何が起きても、配信の判定（終わり方）は変えない。
def report_distribution(client, app_id)
  lines = ['', '### 配り方（読むだけの診断）', '']

  code, body = client.get('/v1/betaGroups', { 'filter[app]' => app_id, 'limit' => 50 })
  if (200..299).cover?(code)
    groups = JSON.parse(body)['data'] || []
    groups.each do |group|
      attributes = group['attributes'] || {}
      kind = attributes['isInternalGroup'] ? '内部' : '外部'
      delivery = attributes['hasAccessToAllBuilds'] ? 'ビルドを自動で配る' : 'ビルドは手で足す'
      puts "テストのグループ: #{kind}・#{delivery}"
      lines << "- テストのグループ: #{kind}・#{delivery}"
    end
    distribution_findings(groups).each do |finding|
      annotate('warning', finding)
      lines << "- **#{finding}**"
    end
  else
    annotate('warning', "テストのグループを読めなかった（HTTP #{code}）")
  end

  code, body = client.get('/v1/builds', {
                            'filter[app]' => app_id,
                            'sort' => '-uploadedDate',
                            'include' => 'preReleaseVersion,buildBetaDetail',
                            'limit' => 5
                          })
  if (200..299).cover?(code)
    lines += ['', '| 版 | ビルド番号 | 処理 | 内部テスト | 期限 | 送った日時 |', '| --- | --- | --- | --- | --- | --- |']
    build_rows(JSON.parse(body)).each do |row|
      puts "最近のビルド: #{row[:version]} (#{row[:build]}) #{row[:processing]} / #{row[:internal]} / " \
           "#{row[:expiry]} / #{row[:uploaded]}"
      lines << "| #{row[:version]} | #{row[:build]} | #{row[:processing]} | #{row[:internal]} | " \
               "#{row[:expiry]} | #{row[:uploaded]} |"
    end
  else
    annotate('warning', "最近のビルドを読めなかった（HTTP #{code}）")
  end

  write_summary(lines)
rescue StandardError => e
  annotate('warning', "配り方の診断を最後まで読めなかった（#{e.class}）")
end

class Client
  def initialize(key_id:, issuer_id:, key_path:)
    @key_id = key_id
    @issuer_id = issuer_id
    @key = OpenSSL::PKey::EC.new(File.read(key_path))
    @token = nil
    @issued_at = 0
  end

  def get(path, params)
    uri = URI::HTTPS.build(host: HOST, path: path)
    uri.query = URI.encode_www_form(params)
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{token}"
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 60) do |http|
      http.request(request)
    end
    [response.code.to_i, response.body.to_s]
  end

  private

  def token
    now = Time.now.to_i
    if @token.nil? || now - @issued_at >= TOKEN_REFRESH_SECONDS
      @token = make_token(@key, key_id: @key_id, issuer_id: @issuer_id, now: now)
      @issued_at = now
    end
    @token
  end
end

# 認証と形の誤りは待っても直らない。それ以外（Apple側の5xx、通信の途切れ）は待ち直す。
TRANSIENT_ERRORS = [
  Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNRESET,
  Errno::ECONNREFUSED, Errno::EHOSTUNREACH, OpenSSL::SSL::SSLError, EOFError
].freeze

def main
  bundle_id = env!('BUNDLE_ID')
  build_number = env!('BUILD_NUMBER')
  client = Client.new(key_id: env!('ASC_KEY_ID'), issuer_id: env!('ASC_ISSUER_ID'), key_path: env!('ASC_KEY_PATH'))

  code, body = client.get('/v1/apps', { 'filter[bundleId]' => bundle_id })
  if [401, 403].include?(code)
    annotate('warning', "鍵の権限でアプリを読めなかった（HTTP #{code}）。送信そのものは成功している")
    puts body
    return 0
  end
  abort "アプリの一覧を取得できませんでした（HTTP #{code}）\n#{body}" unless (200..299).cover?(code)
  app = (JSON.parse(body)['data'] || []).first
  abort "#{bundle_id} のアプリが App Store Connect に見つかりません。" if app.nil?

  puts "アプリ: #{bundle_id}"
  puts "ビルド番号: #{build_number}"

  deadline = Time.now + DEADLINE_SECONDS
  last = nil
  last_response = {}

  loop do
    begin
      code, body = client.get('/v1/builds', {
                                'filter[app]' => app['id'],
                                'filter[version]' => build_number,
                                'include' => 'preReleaseVersion,buildBetaDetail',
                                'limit' => 1
                              })
    rescue *TRANSIENT_ERRORS => e
      puts "#{Time.now.utc.strftime('%H:%M:%S')} 通信が途切れた（#{e.class}）。待ち直す"
      code = nil
    end

    if code && [401, 403].include?(code)
      annotate('warning', "鍵の権限でビルドを読めなかった（HTTP #{code}）。送信そのものは成功している")
      puts body
      return 0
    end
    if code && (400..499).cover?(code)
      # 問い合わせの形が誤っている。待っても直らないので、ここで止めて直す。
      annotate('error', "問い合わせが受け付けられなかった（HTTP #{code}）。このスクリプトの誤り")
      puts body
      return 1
    end

    if code && (200..299).cover?(code)
      last_response = JSON.parse(body)
      verdict, reason = classify(last_response)
      if last != [verdict, reason]
        puts "#{Time.now.utc.strftime('%H:%M:%S')} #{reason}"
        last = [verdict, reason]
      end
      break if %i[ready failed needs_action].include?(verdict)
    end

    break if Time.now >= deadline

    sleep POLL_SECONDS
  end

  verdict, reason = last || [:not_found, '一度も答えが返ってこなかった']
  version = version_of(last_response)
  processing = processing_state_of(last_response)
  internal = internal_state_of(last_response)

  # AIが grep で拾う行。形を変えないこと（.claude/skills/release/SKILL.md が読む）。
  puts "TESTFLIGHT STATUS: #{verdict} version=#{version || '-'} build=#{build_number} " \
       "processingState=#{processing || '-'} internalBuildState=#{internal || '-'}"

  write_summary([
                  '### TestFlight',
                  '',
                  '| 項目 | 値 |',
                  '| --- | --- |',
                  "| 判定 | #{reason} |",
                  "| 版 | #{version || '-'} |",
                  "| ビルド番号 | #{build_number} |",
                  "| 処理 | #{processing || '-'} |",
                  "| 内部テスト | #{internal || '-'} |"
                ])

  report_distribution(client, app['id'])

  case verdict
  when :ready
    annotate('notice', "#{version} (#{build_number}) が内部テスターに配られた")
    0
  when :failed, :needs_action
    annotate('error', "#{version} (#{build_number}): #{reason}")
    1
  else
    # 30分待っても終わらなかった。失敗とは言えないので、見えた状態をそのまま残す。
    annotate('warning', "#{DEADLINE_SECONDS / 60}分待っても確定しなかった。最後の状態: #{reason}")
    0
  end
end

# --- 自己点検 -----------------------------------------------------------------
#
# 本物の鍵も通信も使わずに、間違えると401しか返ってこない部分（署名の形）と、
# 判定の分かれ目を確かめる。CI（pull_request）で毎回走る。

def self_test
  failures = []
  check = lambda do |label, ok|
    puts "#{ok ? 'ok  ' : 'NG  '} #{label}"
    failures << label unless ok
  end

  key = OpenSSL::PKey::EC.generate('prime256v1')
  # 本番と同じく、ファイル（PKCS#8）から読み直した鍵で署名する。
  pem = key.private_to_pem
  reloaded = OpenSSL::PKey::EC.new(pem)
  token = make_token(reloaded, key_id: 'TESTKEY123', issuer_id: 'issuer-0000', now: 1_800_000_000)
  header, payload, signature = token.split('.')

  pad = ->(text) { text + ('=' * ((4 - (text.length % 4)) % 4)) }
  decoded_header = JSON.parse(Base64.urlsafe_decode64(pad.call(header)))
  decoded_payload = JSON.parse(Base64.urlsafe_decode64(pad.call(payload)))
  raw = Base64.urlsafe_decode64(pad.call(signature))

  check.call('トークンは3つに分かれる', [header, payload, signature].none?(&:nil?))
  check.call('ヘッダは ES256 と鍵ID', decoded_header == { 'alg' => 'ES256', 'kid' => 'TESTKEY123', 'typ' => 'JWT' })
  check.call('宛先は appstoreconnect-v1', decoded_payload['aud'] == 'appstoreconnect-v1')
  check.call('有効期限は20分以内', decoded_payload['exp'] - decoded_payload['iat'] <= 20 * 60)
  check.call('署名は64バイト（DERではない）', raw.bytesize == 64)

  r = OpenSSL::BN.new(raw[0, 32], 2)
  s = OpenSSL::BN.new(raw[32, 32], 2)
  der = OpenSSL::ASN1::Sequence.new([OpenSSL::ASN1::Integer.new(r), OpenSSL::ASN1::Integer.new(s)]).to_der
  check.call('署名は鍵で検証できる', key.verify(OpenSSL::Digest.new('SHA256'), der, "#{header}.#{payload}"))

  # 1回の署名だけだと、r や s の頭が0の場合（約1/128）を通らない。何回か回す。
  all_valid = 200.times.all? do |i|
    t = make_token(reloaded, key_id: 'K', issuer_id: 'I', now: 1_800_000_000 + i)
    h, p, sig = t.split('.')
    bytes = Base64.urlsafe_decode64(pad.call(sig))
    next false unless bytes.bytesize == 64

    seq = OpenSSL::ASN1::Sequence.new([
                                        OpenSSL::ASN1::Integer.new(OpenSSL::BN.new(bytes[0, 32], 2)),
                                        OpenSSL::ASN1::Integer.new(OpenSSL::BN.new(bytes[32, 32], 2))
                                      ])
    key.verify(OpenSSL::Digest.new('SHA256'), seq.to_der, "#{h}.#{p}")
  end
  check.call('200回署名しても全部64バイトで検証できる', all_valid)

  build = lambda do |state, internal|
    {
      'data' => [{ 'type' => 'builds', 'attributes' => { 'processingState' => state, 'version' => '2026.1014.0930' } }],
      'included' => [
        { 'type' => 'preReleaseVersions', 'attributes' => { 'version' => '0.2.0' } },
        { 'type' => 'buildBetaDetails', 'attributes' => { 'internalBuildState' => internal } }
      ]
    }
  end

  check.call('一覧に無い → 待つ', classify({ 'data' => [] }).first == :not_found)
  check.call('処理中 → 待つ', classify(build.call('PROCESSING', 'PROCESSING')).first == :waiting)
  check.call('処理済み・グループ未割り当て → 待つ', classify(build.call('VALID', 'READY_FOR_BETA_TESTING')).first == :waiting)
  check.call('処理済み・内部テスト中 → 配られた', classify(build.call('VALID', 'IN_BETA_TESTING')).first == :ready)
  check.call('処理失敗 → 失敗', classify(build.call('FAILED', nil)).first == :failed)
  check.call('不正なビルド → 失敗', classify(build.call('INVALID', nil)).first == :failed)
  check.call('輸出コンプライアンス待ち → 人の操作', classify(build.call('VALID', 'MISSING_EXPORT_COMPLIANCE')).first == :needs_action)
  check.call('版を読める', version_of(build.call('VALID', 'IN_BETA_TESTING')) == '0.2.0')


  auto = [{ 'attributes' => { 'isInternalGroup' => true, 'hasAccessToAllBuilds' => true } }]
  manual = [{ 'attributes' => { 'isInternalGroup' => true, 'hasAccessToAllBuilds' => false } }]
  external = [{ 'attributes' => { 'isInternalGroup' => false, 'hasAccessToAllBuilds' => true } }]
  check.call('内部グループが自動で配る → 指摘なし', distribution_findings(auto).empty?)
  check.call('内部グループが手で足す → 指摘あり', distribution_findings(manual).size == 1)
  check.call('内部グループが無い → 指摘あり', distribution_findings(external).size == 1)

  listing = {
    'data' => [{
      'type' => 'builds', 'id' => 'b1',
      'attributes' => { 'version' => '2026.1015.0300', 'processingState' => 'VALID', 'expired' => false,
                        'uploadedDate' => '2026-10-15T03:00:00Z' },
      'relationships' => {
        'preReleaseVersion' => { 'data' => { 'type' => 'preReleaseVersions', 'id' => 'v1' } },
        'buildBetaDetail' => { 'data' => { 'type' => 'buildBetaDetails', 'id' => 'd1' } }
      }
    }],
    'included' => [
      { 'type' => 'preReleaseVersions', 'id' => 'v1', 'attributes' => { 'version' => '0.2.1' } },
      { 'type' => 'buildBetaDetails', 'id' => 'd1', 'attributes' => { 'internalBuildState' => 'IN_BETA_TESTING' } }
    ]
  }
  row = build_rows(listing).first
  check.call('最近のビルドを表の行にできる',
             !row.nil? && row[:version] == '0.2.1' && row[:build] == '2026.1015.0300' &&
             row[:internal] == 'IN_BETA_TESTING' && row[:expiry] == '有効')
  if failures.empty?
    puts 'self-test: OK'
    0
  else
    puts "self-test: #{failures.size}件 NG"
    1
  end
end

if $PROGRAM_NAME == __FILE__
  exit(ARGV.include?('--self-test') ? self_test : main)
end
