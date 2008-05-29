class WorksController < ApplicationController
  # only registered users and NOT admin should be able to create new works
  before_filter :users_only, :except => [ :index, :show, :destroy ]
  # only authors of a work should be able to edit it
  before_filter :is_author_true, :only => [ :edit, :update ]
  before_filter :set_instance_variables, :only => [ :new, :create, :edit, :update, :preview, :post ]
  before_filter :update_or_create_reading, :only => [ :show ]
  
  auto_complete_for :pseud, :name
  
  def access_denied
    flash[:error] = "Please log in first."
    store_location
    redirect_to new_session_path
    false
  end

  # Sets values for @work, @chapter, @metadata, @pseuds, and @selected
  def set_instance_variables
    if params[:id] # edit, update, preview, post
      @work = Work.find(params[:id])
    elsif params[:work]  # create
      @work = Work.new(params[:work])
    else # new
      @work = Work.new
      @work.chapters.build
      @work.metadata = Metadata.new
    end

    @chapter = @work.chapters.first
    @metadata = @work.metadata

    if @work.authors && !@work.authors.empty?
      @pseuds = @work.authors
      if @work.pseuds && !@work.pseuds.empty?
        @pseuds = (@pseuds + @work.pseuds).uniq
      end 
    elsif @work.pseuds && !@work.pseuds.empty?
      @pseuds = @work.pseuds 
    else
      @pseuds = current_user.pseuds
    end

    if params[:work] && params[:work]["author_attributes"] && params[:work]["author_attributes"]["ids"]
      @selected = params[:work]["author_attributes"]["ids"].collect {|id| id.to_i }
    elsif @work.authors && !@work.authors.empty?
      @selected = @work.authors.collect {|pseud| pseud.id.to_i }
    elsif @work.pseuds && !@work.pseuds.empty?
      @selected = @work.pseuds.collect {|pseud| pseud.id.to_i }
    else
      @selected = current_user.default_pseud.id
    end  
  end
  
  # check if the user's current pseud is one associated with the work
  def is_author
    @work = Work.find(params[:id])
    not (logged_in? && (current_user.pseuds & @work.pseuds).empty?)
  end  
  
  # if is_author returns true allow them to update, otherwise redirect them to the work page with an error message
  def is_author_true
    is_author || [ redirect_to(@work), flash[:error] = 'Sorry, but you don\'t have permission to make edits.' ]
  end
  
  # GET /works
  def index
   # Get only works in the current locale
   if Locale.active && Locale.active.language
      @works = Work.find(:all, 
                          :conditions => ["posted = 1 AND language_id = ?", Locale.active.language.id],
                          :order => "created_at DESC" )
     
    else
      @works = Work.find(:all,
                         :order => "created_at DESC", 
                         :conditions => ["posted = 1"])
    end
  end
  
  # GET /works/1
  # GET /works/1.xml
  def show
    @work = Work.find(params[:id]) 
    @chapters = @work.chapters.find(:all, :order => 'position')
    @comments = @work.find_all_comments
  end
  
  # GET /works/new
  def new
  end

  # POST /works
  def create
    @work.set_initial_version
    if @work.save
      flash[:notice] = 'Work was successfully created.'
      redirect_to preview_work_path(@work)
    else
      @pseuds = current_user.pseuds
      @work.chapters.build 
      @work.metadata = Metadata.new(params[:work][:metadata_attributes])
      render :action => :new 
    end
  end
  
  # GET /works/1/edit
  def edit
    @chapters = Chapter.find(:all, :conditions => {:work_id => @work.id}, :order => "position")
  end
  
  # PUT /works/1
  def update
    @work.attributes = params[:work]
    
    # Display the collected data if we're in preview mode, save it if we're not
    if params[:preview_button]
      @pseuds = (@work.authors + @work.pseuds).uniq
      @selected = @work.authors.collect {|pseud| pseud.id.to_i }
      render :partial => 'preview_edit', :layout => 'application'
    elsif params[:cancel_button]
      # Not quite working yet - should send the user back to wherever they were before they hit edit
      redirect_back_or_default('/')
    elsif params[:edit_button]
      render :partial => 'work_form', :layout => 'application'
    else  
      if @work.update_attributes(params[:work])
        @work.update_minor_version
        flash[:notice] = 'Work was successfully updated.'
        redirect_to(@work)
      else
        render :partial => 'work_form', :layout => 'application' 
      end
    end 
  end
 
  # GET /works/1/preview
  def preview
  end
  
  # POST /works/1/post
  def post
    if params[:cancel_button]
      redirect_back_or_default('/')
    else
      @work.posted = true
      # Will save tags here when tags exist!
      if @work.save
        flash[:notice] = 'Work has been posted!'
        redirect_to(@work)
      else
        render :action => "preview"
      end
    end
  end
  
  # DELETE /works/1
  def destroy
    @work = Work.find(params[:id])
    @work.destroy
    redirect_to(works_url)
  end
  
  def update_positions
    params[:sortable_chapter_list].each_with_index do |id, position|
      Chapter.update(id, :position => position + 1)
    end
    render :nothing => true
  end
  
  protected

  # create a reading object when showing a work, but only if the user has reading 
  # history enabled and is not the author of the work
  def update_or_create_reading
    if logged_in? && current_user.preference.history_enabled
      unless is_author
        reading = Reading.find_or_initialize_by_work_id_and_user_id(@work.id, current_user.id)
        reading.major_version_read, reading.minor_version_read = @work.major_version, @work.minor_version
        reading.save
      end
    end
    true
  end

end
