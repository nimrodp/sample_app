









def dynamic_create

  app_key =  params[:appkey]
  sku = params[:sku]
  domain = params[:domain]
  product_title = params[:product_title]
  product_description = params[:product_description]

  product_url = params[:product_url].to_s
  product_url = "http://#{product_url}" unless product_url =~ /^http/
  product_url = product_url =~ /^http(s?)\:\/\/(\w+)\.(.+)/ ? product_url : request.env["HTTP_REFERER"]

  product_models = params[:product_models]
  product_image_url = params[:product_image_url]
  product_bread_crumbs = params[:product_bread_crumbs]
  review_content = params.fetch(:review_content)
  review_title = params.fetch(:review_title)
  review_score = params.fetch(:review_score)
  reviewer_token = params[:reviewer_token]

  anonymous_user_display_name = "import user" unless params[:display_name]
  anonymous_user_email = "mail@import.user" unless params[:email]

  purchase = false

  @current_user = AnonymousUser.create!(:display_name => anonymous_user_display_name, :email => anonymous_user_email)

  account = Account.find_by_app_key!(app_key)
  product_app = account.products_apps.find_by_domain_key(sku)

  review = nil
  if product_app
    # the product app exists, update attributes if changes found
    product = product_app.product
    product_app.update_attributes(:product_url => product_url) if product_app.product_url != product_url
    product.update_attributes(:name => product_title, :description => product_description) if product.name != product_title or product.description != product_description

    if product_bread_crumbs != product_app.bread_crumbs && !product_bread_crumbs.nil?
      product_app.bread_crumbs = product_bread_crumbs
      product_app.save!
    end
  else
    # the product app doens't exists, create one

    # get the owner of the app_key
    app_owner = account.users.first

    # create product and bundle it to app_key
    # category with id 1 is equal to General in production
    product = app_owner.products.create!(:name => product_title, :category_id => 1, :description => product_description)
    begin
      # create image from product image url
      image = product.images.build
      image.user_id = app_owner.id
      remote_image = open(product_image_url)

      def remote_image.original_filename;
        base_uri.path.split('/').last;
      end

      image.image = remote_image
      image.save!

      product.update_attribute(:featured_image_id, image.id)
    rescue Exception => e
      logger.error "Failed to save image."
    end

    # finally create ProductApp row which bundle between the product and the app
    product_app = ProductsApp.create!(:product_id => product.id, :app_key => app_key, :domain_key => sku, :product_url => product_url, :bread_crumbs => product_bread_crumbs)
  end


  # create the user's review
  review = current_user.reviews_written.build(:title => review_title, :content => review_content, :score => review_score)
  review.app_key = app_key

  # add votes
  review.votes.create!(:vote => vote_type)


  # create mention between the created review and the current product
  review.mentions.create!(:start => 0, :end => 0, :mentionable_type => 'ProductsApp', :mentionable_id => product_app.id)

  publish_review review.id, reviewer_token

  vlad_frog :reviews => [review]

  #send new anonymous event to queue if this is a new anonymous review
  Resque.enqueue(EventHandler, :new_anonymous_user, {"user_id" => @current_user.id}) if @current_user.class == AnonymousUser
  # post this review to the application's social pages
  Resque.enqueue(EventHandler, :new_review, {:review_id => review.id, :shorten_product_url => review.shorten_product_url, :product_app_id => product_app.id})
end