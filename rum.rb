# coding: utf-8

class RUM < Sinatra::Base
  error 400..510 do
    message = case status
              when (401 or 403) then
                "Tú no... ¡úshcale!"
              when 404 then
                "No hay de esos..."
              when 500 then
                "Ya se le tronó el moño a esto..."
              else
                "¡Ay No! Por favor..."
              end

    mustache :error,
             :layout => false,
             :locals => {
               :status => status,
               :message => message
             }
  end

  get '/' do
    post = JSON.parse(Net::HTTP.get(URI('https://blog.revistadelauniversidad.mx/wp-json/wp/v2/posts?_embed&per_page=1')),
                       { :symbolize_names => true }).each { |p|

      begin
        p[:cover] = p[:_embedded][:'wp:featuredmedia'][0][:source_url]
      rescue
        p[:cover] = nil
      end

      begin
        p[:category] = p[:_embedded][:'wp:term'][0][0][:name]
      rescue
        p[:category] = ""
      end
    }.first

    mustache :index,
             :locals => {
               :latest_post => post,
               :articles_suggestion => $db_articles_suggestion.call(nil, 3),
               :latest_releases => $db_releases_latest.call(3),
               :collaborators => $db_starred_collabs.call.shuffle.first(6),
               :suggestions => $db_starred_suggestions.call
             }
  end

  get '/releases-all/?' do
    mustache :releases,
             :locals => { :releases => $db_releases_all.call }
  end

  get '/releases/:id/?' do
    @release = $db_release_by_id.call params[:id]

    halt 404 if not @release

    groups = $db_articles_by_release.call params[:id]

    sections = (0..@release[:metadata][:sections].length-1).map { |i|
      sn = @release[:metadata][:sections][i]

      if sn == 'multimedia'
        groups[i].each { |a|
          a[:is_multimedia] = true

          a[:is_video] = (a[:metadata][:subsection] == "video")
          a[:is_audio] = (a[:metadata][:subsection] == "audio")
        }
      end

      {
        'section_name' => sn,
        'articles' => (sort_like (@release[:metadata][:articles_ids] or []), groups[i])
      }
    }

    mustache :release,
             :locals => {
               :release => @release,
               :sections => sections,
               :quotes => @release[:metadata][:quotes]
             }
  end

  get '/archive/?' do
    mustache :archive,
             :locals => {
               :releases => $db_releases.call,
               :content => Kramdown::Document.new($db_pages_by_id.call("archive")[:content]).to_html
             }
  end

  get '/articles/:id/?' do
    @article = $db_article_by_id.call params[:id]

    halt 404 if not @article

    redirect "/articles/#{params[:id]}/#{@article[:seo_title]}"
  end

  get '/articles/:id/:seo_url/?' do
    @article = $db_article_by_id.call params[:id]

    halt 404 if not @article

    @release = @article[:release]

    begin
      authors_list  =
        @article[:collaborations].
          select { |x| x[:relation] == 'author' }.
          map    { |x| collab_link x[:collabs] }.
          join(", ")

      authors_plain_list  =
        @article[:collaborations].
          select { |x| x[:relation] == 'author' }.
          map    { |x| x[:collabs][:name] }.
          join(", ")

      collabs  = @article[:collaborations].
                   select { |x| x[:relation] != 'author' }.
                   map    { |x|
        x[:collabs][:link] = collab_link(x[:collabs])
        x[:collabs][:long_relation] = case x[:relation]
                                      when 'translator' then 'Traducción de'
                                      when 'editor'     then 'Edición de'
                                      when 'co-author'  then 'co-escrito por'
                                      else x[:relation]
                                      end
        x[:collabs]
      }
    rescue
      authors_list = nil
      collabs = nil
    end

    @title = "#{ @article[:plain_title] } | #{ authors_plain_list }"

    if @article[:doc_only]
      mustache :article_doc_only,
               :locals => {
                 :article => @article,
                 :collabs => collabs,
                 :authors_list => authors_list
               }
    else
      mustache :article,
               :locals => {
                 :articles_suggestion => $db_articles_suggestion.call(@article[:id], 3),
                 :article => @article,
                 :collabs => collabs,
                 :authors_list => authors_list
               }
    end
  end

  get '/collabs/?' do
    all_collabs = $db_collabs.call.sort_by { |x| x[:lname] }

    mustache :collabs,
             :locals => {
               :groups =>  $db_collabs_index_letters.call,
               :collabs => all_collabs.select { |x| x[:starred] }.shuffle.first(12)
             }
  end

  get '/collabs/:id/?' do
    @collab = $db_collab_by_id.call params[:id]

    halt 404 if not @collab

    redirect "/collabs/#{params[:id]}/#{@collab[:seo_name]}"
  end

  get '/collabs/:id/:seo_url/?' do
    @collab = $db_collab_by_id.call params[:id]

    halt 404 if not @collab

    mustache :collab,
             :locals => {
               :groups => $db_collabs_index_letters.call,
               :collab => @collab,
               :articles => @collab[:articles]
             }
  end

  get '/collabs-lastname/:letter' do
    mustache :collabs,
             :locals => {
               :groups => $db_collabs_index_letters.call,
               :collabs => $db_collabs_by_letter.call(params[:letter])
             }
  end

  get '/tags/:tags' do
    tags = params[:tags].force_encoding("UTF-8").downcase.split(",")

    mustache :tag,
             :locals => {
               :tags => tags,
               :articles => $db_articles_by_tags.call(tags)
             }
  end

  get '/suggestions/?' do
    mustache :suggestions,
             :locals => { :suggestions => $db_suggestions.call }
  end

  get '/blog' do
    # TODO: stop using wordpress... it smells

    months_spa = [nil, "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"]

    posts = JSON.parse(Net::HTTP.get(URI('https://blog.revistadelauniversidad.mx/wp-json/wp/v2/posts?_embed')),
                       { :symbolize_names => true }).each { |p|

      d = Date.parse(p[:date])

      p[:created] = "#{d.day} de #{months_spa[d.month]} de #{d.year}"

      begin
        p[:category] = p[:_embedded][:'wp:term'][0][0][:name]
      rescue
        p[:category] = ""
      end
    }

    mustache :blog,
             :locals => {
               :posts => posts
             }
  end

  get '/search/?' do
    mustache :search
  end

  get %r{/(about|directory|related|find_us|privacy|publish)/?} do
    mustache :md,
             :locals => { :content => $db_pages_by_id.call(params[:captures].first)[:content] }
  end
end
