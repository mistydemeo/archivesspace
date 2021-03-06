class JobsController < ApplicationController

  set_access_control "view_repository" => [:index, :show, :log, :status, :records, :download_file ]
  set_access_control "import_records" => [:new, :create]
  set_access_control "cancel_importer_job" => [:cancel]
  
  include ExportHelper

  def index
    @active_jobs = Job.active
    @search_data = Job.archived(selected_page)
  end

  def new
    @job = JSONModel(:job).new._always_valid!
    @job_types = job_types
    @import_types = import_types
    @report_data = JSONModel::HTTP::get_json("/reports")
  end

  def create

    job_data = case params['job']['job_type']
               when 'find_and_replace_job'
                 params['find_and_replace_job'].reject{|k,v| k === '_resolved'}
               when 'print_to_pdf_job'
                 params['print_to_pdf_job'].reject{|k,v| k === '_resolved'}
               when 'report_job' 
                 params['report_job']
               when 'import_job'
                 params['import_job']
               end


    job_data["repo_id"] ||= session[:repo_id]
    begin
      job = Job.new(params['job']['job_type'], job_data, Hash[Array(params['files']).reject(&:blank?).map {|file|
                                  [file.original_filename, file.tempfile]}], 
                                  params['job']['job_params']
                   )

    rescue JSONModel::ValidationException => e

      @exceptions = e.invalid_object._exceptions
      @job = e.invalid_object
      @job_types = job_types
      @import_types = import_types

      if params[:iframePOST] # IE saviour. Render the form in a textarea for the AjaxPost plugin to pick out.
        return render_aspace_partial :partial => "jobs/form_for_iframepost", :status => 400
      else
        return render_aspace_partial :partial => "jobs/form", :status => 400
      end
    end

    if params[:iframePOST] # IE saviour. Render the form in a textarea for the AjaxPost plugin to pick out.
      render :text => "<textarea data-type='json'>#{job.upload.to_json}</textarea>"
    else
      render :json => job.upload
    end
  end


  def show
    @job = JSONModel(:job).find(params[:id], "resolve[]" => "repository")
    @files = JSONModel::HTTP::get_json("#{@job['uri']}/output_files") 
  end


  def cancel
    Job.cancel(params[:id])

    redirect_to :action => :show
  end


  def log
    self.response_body = Enumerator.new do |y|
      Job.log(params[:id], params[:offset] || 0) do |response|
        y << response.body
      end
    end
  end


  def status
    job = JSONModel(:job).find(params[:id])

    json = {
        :status => job.status
    }

    if job.status === "queued"
      json[:queue_position] = job.queue_position
      json[:queue_position_message] = job.queue_position === 0 ? I18n.t("job._frontend.messages.queue_position_next") : I18n.t("job._frontend.messages.queue_position", :position => (job.queue_position+1).ordinalize)
    end

    render :json => json
  end


  def download_file
    @job = JSONModel(:job).find(params[:job_id], "resolve[]" => "repository")
    
    if @job.job.has_key?("format") && !@job.job["format"].blank? 
        format = @job.job["format"]
    else
        format = "pdf"
    end 
    url = "/repositories/#{JSONModel::repository}/jobs/#{params[:job_id]}/output_files/#{params[:id]}"
    stream_file(url, {:format => format, :filename => "job_#{params[:job_id].to_s}_file_#{params[:id].to_s}" } ) 
  end
  
  
  def records
    @search_data = Job.records(params[:id], params[:page] || 1)
    render_aspace_partial :partial => "jobs/job_records"
  end

  private

  def selected_page
    [Integer(params[:page] || 1), 1].max
  end

  def job_types
    Job.available_types.map {|e| [I18n.t("enumerations.job_type.#{e}"), e]}
  end

  def import_types
    Job.available_import_types.map {|e| [I18n.t("import_job.import_type_#{e['name']}"), e['name']]}
  end


  def stream_file(request_uri, params = {})

    filename = params[:filename] ? "#{params[:filename]}.#{params[:format]}" : "ead.pdf"



    respond_to do |format|
      format.html {
        self.response.headers["Content-Type"] ||= "application/#{params[:format]}" 
        self.response.headers["Content-Disposition"] = "attachment; filename=#{filename}"
        self.response.headers['Last-Modified'] = Time.now.ctime.to_s

        self.response_body = Enumerator.new do |y|
          xml_response(request_uri, params) do |chunk, percent|
            y << chunk if !chunk.blank?
          end
        end
      }
    end
  end



end
