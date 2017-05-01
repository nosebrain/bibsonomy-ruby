# BibSonomy

[BibSonomy](http://www.bibsonomy.org/) client for Ruby

[![Gem Version](https://badge.fury.io/rb/bibsonomy.svg)](http://badge.fury.io/rb/bibsonomy)
[![Build Status](https://travis-ci.org/rjoberon/bibsonomy-ruby.svg?branch=master)](https://travis-ci.org/rjoberon/bibsonomy-ruby)
[![Coverage Status](https://coveralls.io/repos/rjoberon/bibsonomy-ruby/badge.svg)](https://coveralls.io/r/rjoberon/bibsonomy-ruby)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'bibsonomy'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install bibsonomy

## Usage

Getting posts from BibSonomy:

```ruby
require 'bibsonomy'
api = BibSonomy::API.new('yourusername', 'yourapikey', 'ruby')
posts = api.get_posts_for_user('jaeschke', 'publication', ['myown'], 0, 20)
```

Rendering posts with [CSL](http://citationstyles.org/):

```ruby
require 'bibsonomy/csl'
csl = BibSonomy::CSL.new('yourusername', 'yourapikey')
html = csl.render('jaeschke', ['myown'], 100)
print html
```

A command line wrapper to the CSL renderer:

```ruby
#!/usr/bin/ruby
require 'bibsonomy/csl'
print BibSonomy::main(ARGV)
```

## Testing

Get an API-Key from <http://www.bibsonomy.org/settings?selTab=1> and
then run the following commands:

```shell
export BIBSONOMY_USER_NAME="yourusername"
export BIBSONOMY_API_KEY="yourapikey"
bundle exec rake test
```

## Jekyll

A [Jekyll](http://jekyllrb.com/) plugin:

```ruby
# coding: utf-8
require 'time'
require 'bibsonomy/csl'

module Jekyll
  include Liquid::StandardFilters
  Syntax = /(#{Liquid::QuotedFragment}+)?/
  
  class BibSonomyPostList < Liquid::Tag
    def initialize(tag_name, text, tokens)
      super
      
      @attributes = {}
      if text =~ Syntax
        text.scan(Liquid::TagAttributes) do |key, value|
          #p key + ":" + value
          if @attributes.has_key?(key)
            current_value = @attributes[key]
            new_value = [current_value]
            new_value << value
            @attributes[key] = new_value
          else
            @attributes[key] = value
          end
        end
      else
        raise SyntaxError.new("Syntax Error in 'bibsonomy' - Valid syntax: bibsonomy user:x tag:x number_of_posts:x]")
      end
      @user = @attributes['user']
      
      @tags = @attributes['tag']
      # if tags is only specified onces, convert string to array
      if !@tags.kind_of?(Array)
        @tags = [@tags]
      end
      
      @grouping = @attributes['group'] == 'true'
      @show_group_menu = @attributes['group_menu'] == 'true'
      
      @number_of_publications = @attributes['number_of_posts']
      
      @csl_style = @attributes['csl-style']
      
      # document handling
      @pdf_postfix_preferred = @attributes['pdf_postfix']
      if !@pdf_postfix_preferred.end_with? ".pdf"
        @pdf_postfix_preferred += ".pdf"
      end
      @show_pdf_previews = @attributes['show_pdf_previews'] == 'true'
      
      # action menu
      @link_pdfs = @attributes['pdfs'] == 'true'
      @show_bibtex = @attributes['include_bibtex'] == 'true'
      @show_abstract = @attributes['show_abstracts'] == 'true'
      @show_doi = @attributes['show_doi_links'] == 'true'
      @show_link = @attributes['show_links'] == 'true'
      @system_link = @attributes['show_system_links'] == 'true'
    end

    def render(context)
      site = context.registers[:site]
      
      # get global config for the tag
      config = site.config['bibsonomy'] || {}
      
      user_name = config['apiuser']
      api_key = config['apikey']
      
      renderer = BibSonomy::CSL.new(user_name, api_key)
      if @link_pdfs
        document_dir = config['document_directory']
        
        renderer.pdf_dir = document_dir
        renderer.public_doc_postfix = @pdf_postfix_preferred
      end
      
      renderer.link_pdfs
      
      if @show_pdf_previews
        preview_dir = config['preview_directory']
        
        renderer.pdf_previews_dir = preview_dir
      end
      
      renderer.bibtex_embedded = @show_bibtex
      renderer.bibtex_link = false
      
      renderer.css_class = "publication-list"
      
      renderer.doi_link = @show_doi
      renderer.url_link = @show_link
      renderer.bibsonomy_link = @system_link
      renderer.show_abstract = @show_abstract
      
      renderer.year_headings = @grouping
      renderer.show_group_menu = @show_group_menu

      # CSL style for rendering
      renderer.style = @csl_style
      
      html = renderer.render(@user, @tags, @number_of_publications)
      
      context.registers[:page]["date"] = Time.new
      return html
    end
    
  end
end

Liquid::Template.register_tag('bibsonomy_publication_list', Jekyll::BibSonomyPostList)
```

The plugin can be used inside Markdown files as follows:

```Liquid
{% bibsonomy_publication_list
	user:jaeschke
	tag:myown
	number_of_posts:100
	csl-style:springer-lecture-notes-in-computer-science
	group:true
	group_menu:true
	pdfs:true
	include_bibtex:true
	show_doi_links:true
	show_links:true
	show_pdf_previews:false
	show_abstracts:true
	pdf_postfix:_oa
	show_system_links:false
%}
```

Add the following options to your `_config.yml`:

```YAML
bibsonomy:
  url: https://www.bibsonomy.org
  apiuser: yourusername
  apikey: yourapikey
  document_directory: pdf
  preview_directory: preview
```

For an example, have a look at [my publication list](http://www.kbs.uni-hannover.de/~jaeschke/publications.html).


## Contributing

1. Fork it ( https://github.com/rjoberon/bibsonomy-ruby/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
