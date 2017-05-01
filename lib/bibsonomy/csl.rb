# coding: utf-8

require 'optparse'
require 'citeproc'
require 'csl/styles'
require 'json'
require 'bibsonomy'

#
# Generates a list of publication posts from BibSonomy
#
# required parameters:
# - user name
# - api key
# optional parameters:
# - user name
# - tags
# - number of posts
# - style
# - directory
#
# Changes:
# 2015-02-24
# - initial version
#
# @todo escape data
# @todo make sorting, etc. configurable
# @todo automatically rename files (TODO: CSL lacks BibTeX key)
# @todo add intra_hash, user_name, etc. to CSL (cf. https://bitbucket.org/bibsonomy/bibsonomy/issue/2411/)
# @todo integrate AJAX abstract
# @todo make all options available via command line
#
# @author Robert Jäschke

module BibSonomy
  class CSL
    
    # @return [String] the output directory for downloaded PDF files. If set to `nil`, no documents are downloaded. (default: `nil`)
    attr_accessor :pdf_dir
    
    # @return [String] the output directory for downloaded PDF preview files. If set to `nil`, no previews are downloaded. (default: `nil`)
    attr_accessor :pdf_previews_dir
    
     # @return [Boolean] whether links to pdfs should be rendered. (default: `true`)
    attr_accessor :link_pdfs

    # @return [String] the {http://citationstyles.org/ CSL} style used for rendering. (default: `apa.csl`)
    attr_accessor :style

    # @return [Boolean] whether year headings shall be rendered. (default: `true`)
    attr_accessor :year_headings
    
    # @return [Boolean] whether a group menu shall be rendered. (default: `true`)
    attr_accessor :show_group_menu

    # @return [String] the CSS class used to render the surrounding `<ul>` list (default: 'publications')
    attr_accessor :css_class

    # @return [Boolean] whether links for DOIs shall be rendered. (default: `true`)
    attr_accessor :doi_link

    # @return [Boolean] whether URLs of posts shall be rendered. (default: `true`)
    attr_accessor :url_link
    
    # @return [Boolean] whether links to the BibTeX data of a post (in BibSonomy) shall be rendered. (default: `true`)
    attr_accessor :bibtex_link

    # @return [Boolean] whether links to BibSonomy shall be rendered. (default: `true`)
    attr_accessor :bibsonomy_link

    # @return [String] the separator between options. (default: ' | ')
    attr_accessor :opt_sep
    
    # @return [Boolean] whether the BibTeX should be embedded into the html output. (default: 'false')
    attr_accessor :bibtex_embedded
    
    # @return [Boolean] whether the abstract should be included in the html output. (default: 'false')
    attr_accessor :show_abstract

    # @return [String] When a post has several documents and the
    #   filename of one of them ends with `public_doc_postfix`, only
    #   this document is downloaded and linked, all other are
    #   ignored. (default: '_oa.pdf')
    attr_accessor :public_doc_postfix

    #
    # Create a new BibSonomy instance.
    #
    # @param user_name [String] the BibSonomy user name
    # @param api_key [String] the API key of the user (get at http://www.bibsonomy.org/settings?selTab=1)
    def initialize(user_name, api_key)
      super()
      
      # setting some defaults
      @style = 'apa.csl'
      
      @pdf_dir = nil
      @pdf_previews_dir = nil
      @link_pdfs = true
      
      @css_class = 'publications'
      @year_headings = true
      @public_doc_postfix = '_oa.pdf'
      
      # grouping
      @show_group_menu = false

      # optional parts to be rendered (or not)
      @doi_link = true
      @url_link = true
      @bibtex_link = true
      @bibtex_embedded = false
      @show_abstract = false
      @bibsonomy_link = true
      @opt_sep = ' | '
      
      @user_name = user_name
      @api_key = api_key
      
      @bibsonomy = BibSonomy::API.new(@user_name, @api_key, 'csl')
      @rest_client_bibtex = BibSonomy::API.new(@user_name, @api_key, 'bibtex')
    end

    #
    # Download `count` posts for the given `user` and `tag(s)` and render them with {http://citationstyles.org/ CSL}.
    #
    # @param user [String] the name of the posts' owner
    # @param tags [Array<String>] the tags that all posts must contain (can be empty)
    # @param count [Integer] number of posts to download
    # @return [String] the rendered posts as HTML
    def render(user, tags, count)
      # get posts from BibSonomy
      posts = JSON.parse(@bibsonomy.get_posts_for_user(user, 'publication', tags, 0, count))

      # render them with citeproc
      cp = CiteProc::Processor.new style: @style, format: 'html'
      cp.import posts

      # to check for duplicate file names
      file_names = []

      # sort posts by year
      sorted_keys = posts.keys.sort { |a,b| get_sort_posts(posts[b], posts[a]) }

      result = "<script>function toggleId(id) {
    var element = document.getElementById(id);
    element.style.display = (element.style.display == 'none' || element.style.display == '') ? 'block' : 'none';
    return false;
}</script>"

      # use invalid year to get first heading
      last_year = -1
      
      # complete publication list
      publication_list_html = ""
      headings = []

      result += "<ul class='#{@css_class}'>\n"
      for post_id in sorted_keys
        post = posts[post_id]

        # print heading
        if @year_headings
          year = get_year(post)
          if year != last_year
            last_year = year
            publication_list_html += "</ul>\n<h3><a name='group_#{year}'></a>" + last_year + "</h3>\n<ul class='#{@css_class}'>\n"
            
            # track headings
            headings << year
          end
        end
        
        # extract the post's id
        intra_hash, user_name = get_intra_hash(post_id)
        publication_list_html += "<li class='" + post["type"] + "'><div class='publication-info'>"
        
        if @pdf_previews_dir
          for doc in get_public_docs(post["documents"])
            doc_name = doc['fileName']
            preview_path = download_preview(@bibsonomy, @pdf_previews_dir, user_name, intra_hash, doc_name, "small")
            publication_list_html += "<div class='preview_container'>"
            if @link_pdfs
              doc_pdf_path = get_document_path(@pdf_dir, doc_name)
              publication_list_html += "<a href='#{doc_pdf_path}'>"
            end
            publication_list_html += "<img class='preview' src='#{preview_path}' />"
            if @link_pdfs
              publication_list_html += "</a>"
            end
            publication_list_html +="</div>"
          end
        end
        
        # render metadata
        csl = cp.render(:bibliography, id: post_id)
        publication_list_html += "<div class='item'>#{csl[0]}</div></div>"

        # optional parts
        options = []
        
        # content to add after the action menu
        publication_extra_html = ""
        
        # attach abstract
        if @show_abstract
          abstract = post['abstract']
          
          if abstract != ""
            abstract_id = post_id + "_abstract"
            hide_menu = get_hide_menu(abstract_id, "Abstract")
            options << get_show_menu(abstract_id, "abstract", "Abstract")
            publication_extra_html += "<div class='abstract' id='#{abstract_id}'>#{abstract}#{hide_menu}</div>"
          end
        end
        
        # attach BibTeX
        if @bibtex_link
          options << "<a href='http://www.bibsonomy.org/bib/publication/#{intra_hash}/#{user_name}'>BibTeX</a>"
        elsif @bibtex_embedded
          bibtex_id = post_id + "_bibtex"
          bibtex = @rest_client_bibtex.get_post(user_name, intra_hash)
          hide_menu = get_hide_menu(bibtex_id, "BibTeX")
          publication_extra_html += "<div class='bibtex' id='#{bibtex_id}'><pre>#{bibtex.force_encoding 'UTF-8'}</pre>#{hide_menu}</div>"
          options << get_show_menu(bibtex_id, "bibtex", "BibTeX")
        end
        
        # attach documents
        if @pdf_dir
          for doc in get_public_docs(post["documents"])
            # fileHash, fileName, md5hash, userName
            file_path = get_document(@bibsonomy, intra_hash, user_name, doc, @pdf_dir, file_names)
            options << "<a href='#{file_path}'>PDF</a>"
          end
        end
        # attach DOI
        doi = post["DOI"]
        if @doi_link and doi != ""
          options << "DOI: <a href='https://dx.doi.org/#{doi}'>#{doi}</a>"
        end
        # attach URL
        url = post["URL"]
        if @url_link and url != ""
          options << "<a href='#{url}'>URL</a>"
        end
        
        # attach link to BibSonomy
        if @bibsonomy_link
          options << "<a href='http://www.bibsonomy.org/publication/#{intra_hash}/#{user_name}'>BibSonomy</a>"
        end

        # attach options
        if options.length > 0
          publication_list_html += "<ul class='publication-actions'>"
          for option in options
            publication_list_html += "<li>#{option}</li>"
          end
          publication_list_html += "</ul>"
        end
        
        publication_list_html += publication_extra_html

        publication_list_html += "</li>\n"
      end
      publication_list_html += "</ul>\n"
      
      if @show_group_menu
        result += "<ul class='publication-actions'>"
        for heading in headings
          result += "<li><a href='#group_#{heading}'>#{heading}</a></li>"
        end
        result += "</ul>"
      end
      
      result += publication_list_html

      return result
    end


    #
    # private methods follow
    #
    private
    
    def get_year(post)
      issued = post["issued"]
      # if the post contains only a "year" field, it is contained in
      # the field "literal"
      if issued["literal"]
        return issued["literal"]
      else
        # otherwise, the date can be contained in the "raw" field
        # TODO: extract the year ([12][0-9]{3}) from that field
        return issued["raw"]
      end
    end

    def get_sort_posts(a, b)
      person_a = a["author"]
      if person_a.length == 0
        person_a = a["editor"]
      end
      person_b = b["author"]
      if person_b.length == 0
        person_b = b["editor"]
      end
      # we switch the order of person_b and person_a, to sort
      # descending by year but ascending by person name
      return [get_year(a), a["type"], person_b[0]["family"]] <=> [get_year(b), b["type"], person_a[0]["family"]]
    end

    #
    # only show PDF files
    #
    def get_public_docs(documents)
      result = []
      for doc in documents
        file_name = doc["fileName"]
        if file_name.end_with? ".pdf"
          if documents.length < 2 or file_name.end_with? @public_doc_postfix
            result << doc
          end
        end
      end
      return result
    end

    def warn(m)
      print("WARN: " + m + "\n")
    end

    #
    # downloads the documents for the posts (if necessary)
    #
    def get_document(bib, intra_hash, user_name, doc, dir, file_names)
      # fileHash, fileName, md5hash, userName
      file_name = doc["fileName"]
      # strip doc prefix for public documents
      if file_name.end_with? @public_doc_postfix
        file_name = file_name[0, file_name.length - @public_doc_postfix.length] + ".pdf"
      end
      # check for possible duplicate file names
      if file_names.include? file_name
        warn "duplicate file name " + file_name + " for post " + intra_hash
      end
      # remember file name
      file_names << file_name
      # produce file path
      file_path = dir + "/" + file_name
      # download PDF if it not already exists
      if not File.exists? file_path
        pdf, mime = bib.get_document(user_name, intra_hash, doc["fileName"])
        if pdf == nil
          warn "could not download file " + intra_hash + "/" + user_name + "/" + file_name
        else
          File.binwrite(file_path, pdf)
        end
      end
      return file_path
    end
    
    def download_preview(rest_client, base_path_preview, user_name, intra_hash, file_name, size)
      folder = base_path_preview + "/" + size + "/"
      if !File.directory?(folder)
        warn "creating folder #{folder}"
        FileUtils::mkdir_p folder
      end
      file_path = folder + file_name + ".jpg"
      
      # download preview if it does not already exist
      # FIXME: use rest client
      if not File.exists? file_path
        @conn = Faraday.new(:url => $API_URL) do |faraday|
          faraday.request  :url_encoded             # form-encode POST params
          faraday.adapter  Faraday.default_adapter
        end
        @conn.basic_auth(@user_name, @api_key)
        response = @conn.get rest_client.get_document_href(user_name, intra_hash, file_name), { :preview => size }
        image = response.body
        # image, mime = rest_client.get_document_preview(user_name, intra_hash, file_name, "small")
        if image == nil
          warn "could not download preview " + intra_hash + "/" + user_name + "/" + file_name
        else
          File.binwrite(file_path, image)
        end
      end
      return file_path
    end
    
    def get_document_path(base_path, file_name)
      return base_path + "/" + file_name
    end
    
    # format of the post ID for CSL: [0-9a-f]{32}USERNAME
    def get_intra_hash(post_id)
      return [post_id[0, 32], post_id[32, post_id.length]]
    end
    
    # UI build methods
    def get_hide_menu(id, what_to_hide)
      return " <a href='hide' onclick='return toggleId(\"#{id}\");'>Hide #{what_to_hide}</a>"
    end
    
    def get_show_menu(id, anchor, text)
      return "<a class='publication-toggle' href='##{anchor}' onclick='return toggleId(\"#{id}\");'>#{text}</a>"
    end

  end


  # Parse command line options
  #
  # @param args [Array<String>] command line options
  # @return [String] the rendered posts as HTML
  def self.main(args)

    # setting default options
    options = OpenStruct.new
    options.documents = false
    options.directory = nil
    options.tags = []
    options.style = "apa.csl"
    options.posts = 1000

    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: csl.rb [options] user_name api_key"

      opts.separator ""
      opts.separator "Specific options:"

      # mandatory arguments are handled separately

      # optional arguments
      opts.on('-u', '--user USER', 'return posts for USER instead of user') { |v| options[:user] = v }
      opts.on('-t', '--tags TAG,TAG,...', Array, 'return posts with the given tags') { |v| options[:tags] = v }
      opts.on('-s', '--style STYLE', 'use CSL style STYLE for rendering') { |v| options[:style] = v }
      opts.on('-n', '--number-of-posts [COUNT]', Integer, 'number of posts to download') { |v| options[:posts] = v }
      opts.on('-d', '--directory DIR', 'target directory', '  (if not given, no documents are downloaed)') { |v| options[:directory] = v }

      opts.separator ""
      opts.separator "Common options:"

      opts.on('-h', '--help', 'show this help message and exit') do
        puts opts
        exit
      end

      opts.on_tail('-v', "--version", "show version") do
        puts BibSonomy::VERSION
        exit
      end

    end

    opt_parser.parse!(args)

    # handle mandatory arguments
    begin
      mandatory = [:user_name, :api_key]
      missing = []

      options[:api_key] = args.pop
      missing << :api_key unless options[:api_key]

      options[:user_name] = args.pop
      missing << :user_name unless options[:user_name]

      if not missing.empty?
        puts "Missing options: #{missing.join(', ')}"
        puts opt_parser
        exit
      end
    rescue OptionParser::InvalidOption, OptionParser::MissingArgument
      puts $!.to_s
      puts opt_parser
      exit
    end

    # set defaults for optional arguments
    options[:user] = options[:user_name] unless options[:user]

    #
    # do the actual work
    #
    csl = BibSonomy::CSL.new(options[:user_name], options[:api_key])
    csl.pdf_dir = options[:directory]
    csl.style = options[:style]

    html = csl.render(options[:user], options[:tags], options[:posts])

    return html

  end

end
