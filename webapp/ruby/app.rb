require 'sinatra/base'
require 'mysql2'
require 'mysql2-cs-bind'
require 'erubis'
require 'rack-lineprof'
require 'active_support'
require 'active_support/all'

module Ishocon1
  class AuthenticationError < StandardError; end
  class PermissionDenied < StandardError; end
end

class Ishocon1::WebApp < Sinatra::Base
  session_secret = ENV['ISHOCON1_SESSION_SECRET'] || 'showwin_happy'
  use Rack::Session::Cookie, key: 'rack.session', secret: session_secret
  #use Rack::Lineprof
  set :erb, escape_html: true
  set :public_folder, File.expand_path('../public', __FILE__)
  set :protection, true

  class << self
    def cache
      @cache ||= ActiveSupport::Cache.lookup_store(:memory_store)
    end
  end

  helpers do
    def config
      @config ||= {
        db: {
          host: ENV['ISHOCON1_DB_HOST'] || 'localhost',
          port: ENV['ISHOCON1_DB_PORT'] && ENV['ISHOCON1_DB_PORT'].to_i,
          username: ENV['ISHOCON1_DB_USER'] || 'ishocon',
          password: ENV['ISHOCON1_DB_PASSWORD'] || 'ishocon',
          database: ENV['ISHOCON1_DB_NAME'] || 'ishocon1'
        }
      }
    end

    def db
      return Thread.current[:ishocon1_db] if Thread.current[:ishocon1_db]
      client = Mysql2::Client.new(
        host: config[:db][:host],
        port: config[:db][:port],
        username: config[:db][:username],
        password: config[:db][:password],
        database: config[:db][:database],
        reconnect: true
      )
      client.query_options.merge!(symbolize_keys: true)
      Thread.current[:ishocon1_db] = client
      client
    end

    def time_now_db
      Time.now - 9 * 60 * 60
    end

    def authenticate(email, password)
      user = db.xquery('SELECT * FROM users WHERE email = ?', email).first
      fail Ishocon1::AuthenticationError unless user[:password] == password
      session[:user_id] = user[:id]
      session[:user_name] = user[:name]
    end

    def authenticated!
      fail Ishocon1::PermissionDenied unless current_user
    end

    def current_user
      return unless session[:user_id]
      {
        id: session[:user_id],
        name: session[:user_name]
      }
    end

    def buy_product(product_id, user_id)
      db.xquery('INSERT INTO histories (product_id, user_id, created_at) VALUES (?, ?, ?)', \
        product_id, user_id, time_now_db)
    end

    def already_bought?(product_id)
      return false unless current_user
      cache_key = "user_#{current_user[:id]}_has_product_#{product_id}"
      return true if cache.exist?(cache_key)

      count = db.xquery('SELECT count(*) as count FROM histories WHERE product_id = ? AND user_id = ?', \
                        product_id, current_user[:id]).first[:count]
      if count > 0
        cache.write(cache_key, 1)
        return true
      end
      false
    end

    def create_comment(product_id, user_id, content)
      db.xquery('INSERT INTO comments (product_id, user_id, content, created_at) VALUES (?, ?, ?, ?)', \
        product_id, user_id, content, time_now_db)
    end

    def cache
      self.class.cache
    end
  end

  error Ishocon1::AuthenticationError do
    session[:user_id] = nil
    halt 401, erb(:login, layout: false, locals: { message: 'ログインに失敗しました' })
  end

  error Ishocon1::PermissionDenied do
    halt 403, erb(:login, layout: false, locals: { message: '先にログインをしてください' })
  end

  get '/login' do
    session.clear
    erb :login, layout: false, locals: { message: 'ECサイトで爆買いしよう！！！！' }
  end

  post '/login' do
    authenticate(params['email'], params['password'])
    redirect '/'
  end

  get '/logout' do
    session[:user_id] = nil
    session.clear
    redirect '/login'
  end

  get '/' do
    page = params[:page].to_i || 0
    offset = page * 50
    ids = [*(offset + 1)..(offset + 50)]
    products = cache.fetch("products_offset_#{offset}") do
      db.xquery("SELECT id, name, LEFT(description, 70), image_path, price FROM products WHERE id IN (?) ORDER BY id DESC", ids).to_a
    end
    cmt_query = <<SQL
SELECT *
FROM comments as c
INNER JOIN users as u
ON c.user_id = u.id
WHERE c.product_id IN (?)
ORDER BY c.created_at DESC
SQL
    comments = db.xquery(cmt_query, products.map {|pr| pr[:id] }).group_by{|c| c[:product_id] }
    products.each do |product|
      cmts = comments[product[:id]]
      product[:c_count] = cmts.length
      product[:comments] = cmts.slice(0, 5)
    end

    erb :index, locals: { products: products }
  end

  get '/users/:user_id' do
    products_query = <<SQL
SELECT p.id, p.name, LEFT(p.description, 70), p.image_path, p.price, h.created_at
FROM histories as h
INNER JOIN products as p
ON h.product_id = p.id
WHERE h.user_id = ?
ORDER BY h.id DESC
LIMIT 30
SQL
    products = db.xquery(products_query, params[:user_id])

    sum_query = <<SQL
SELECT SUM(p.price) as total_pay
FROM histories as h
INNER JOIN products as p
ON h.product_id = p.id
WHERE h.user_id = ?
SQL
    total_pay = db.xquery(sum_query, params[:user_id]).first[:total_pay]

    user = cache.fetch("user_#{params[:user_id]}") do
      db.xquery('SELECT * FROM users WHERE id = ?', params[:user_id]).first
    end
    erb :mypage, locals: { products: products, user: user, total_pay: total_pay }
  end

  get '/products/:product_id' do
    product = cache.fetch("product_#{params[:product_id]}") do
      db.xquery('SELECT * FROM products WHERE id = ?', params[:product_id]).first
    end
    erb :product, locals: { product: product }
  end

  post '/products/buy/:product_id' do
    authenticated!
    buy_product(params[:product_id], current_user[:id])
    redirect "/users/#{current_user[:id]}"
  end

  post '/comments/:product_id' do
    authenticated!
    create_comment(params[:product_id], current_user[:id], params[:content])
    redirect "/users/#{current_user[:id]}"
  end

  get '/initialize' do
    db.query('DELETE FROM users WHERE id > 5000')
    db.query('DELETE FROM products WHERE id > 10000')
    db.query('DELETE FROM comments WHERE id > 200000')
    db.query('DELETE FROM histories WHERE id > 500000')
    "Finish"
  end
end
