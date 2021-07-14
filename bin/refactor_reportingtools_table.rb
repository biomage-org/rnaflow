#!/usr/bin/env ruby

require 'fileutils'

class RefactorReportingtoolsTable

  def initialize(html_path, anno, add_plot_information, pvalue)

    # does not work anymore because the input is now named 'annotation.gene.gtf'
    #species = anno.sub('.gene.gtf','')

    # check if analysis runs on transcripts instead of genes
    $exon_id_2_gene_id = {}
    feature_type = 'gene'
    if anno.include?('.transcript.gtf')
      feature_type = 'transcript'
    end
    if anno.include?('.exon.gtf')
      feature_type = 'exon'
    end

    $add_plots = false
    $add_plots = true if add_plot_information && add_plot_information == 'add_plots'

    # fix for now, we need at some point a more general mechanic to detect the (main) species (host) used. Likely as a parameter
    species = 'na'
    f = File.open(anno, 'r')
    f.each do |line|
      unless line.start_with?('#')
        s = line.split("\t")
        if s[8] && s[8].include?('gene_id')
          gene_id = s[8].split(';')[0].split('gene_id')[1].gsub('"','').chomp.strip
          species = 'eco' if gene_id.start_with?('ER')
          species = 'hsa' if gene_id.start_with?('ENSG')
          species = 'mmu' if gene_id.start_with?('ENSMUSG')
          species = 'mau' if gene_id.start_with?('ENSMAUG')
          species = 'rno' if gene_id.start_with?('ENSRNOG')
          break if species != 'na'
        end
      end
    end
    f.close

    case species
      when 'eco' 
        $scan_feature_id_pattern = 'ER[0-9]+_[0-9]+'
        $ensembl_url = 'https://bacteria.ensembl.org/Escherichia_coli_k_12/Gene/Summary?g='
      when 'hsa'
        $scan_feature_id_pattern = 'ENSG[0-9]+'
        $ensembl_url = 'https://ensembl.org/Homo_sapiens/Gene/Summary?g='
        if feature_type == 'transcript'
          $scan_feature_id_pattern = 'ENST[0-9]+'
          $ensembl_url = 'https://ensembl.org/Homo_sapiens/Gene/Summary?t='  
        end
        if feature_type == 'exon'
          $scan_feature_id_pattern = 'ENSE[0-9]+'
        end
      when 'mmu'
        $scan_feature_id_pattern = 'ENSMUSG[0-9]+'
        $ensembl_url = 'https://ensembl.org/Mus_musculus/Gene/Summary?g='
        if feature_type == 'transcript'
          $scan_feature_id_pattern = 'ENSMUST[0-9]+'
          $ensembl_url = 'https://ensembl.org/Mus_musculus/Gene/Summary?t='
        end
        if feature_type == 'exon'
          $scan_feature_id_pattern = 'ENSMUSE[0-9]+'
        end
      when 'mau'
        $scan_feature_id_pattern = 'ENSMAUG[0-9]+'
        $ensembl_url = 'https://ensembl.org/Mesocricetus_auratus/Gene/Summary?g='
        if feature_type == 'transcript'
          $scan_feature_id_pattern = 'ENSMAUT[0-9]+'
          $ensembl_url = 'https://ensembl.org/Mesocricetus_auratus/Gene/Summary?t='
        end
        if feature_type == 'exon'
          $scan_feature_id_pattern = 'ENSMAUE[0-9]+'
        end
      when 'rno'
        $scan_feature_id_pattern = 'ENSRNOG[0-9]+'
        $ensembl_url = 'https://ensembl.org/Rattus_norvegicus/Gene/Summary?g='
        if feature_type == 'transcript'
          $scan_feature_id_pattern = 'ENSRNOT[0-9]+'
          $ensembl_url = 'https://ensembl.org/Rattus_norvegicus/Gene/Summary?t='
        end
        if feature_type == 'exon'
          $scan_feature_id_pattern = 'ENSRNOE[0-9]+'
        end
      else
        $scan_feature_id_pattern = false
        $ensembl_url = false
    end

		$id2name = {}
    $id2biotype = {}
    $id2pos = {}
    gtf = File.open(anno,'r')
    gtf.each do |line|
      
      s = line.split("\t")
      
      feature_name = 'NA'
      if line.include?('gene_name')
        feature_name = s[8].split('gene_name')[1].split(';')[0].gsub('"','').strip
      end 
      if feature_type == 'transcript' && line.include?('transcript_name')
        # update feature name to transcript_name
        feature_name = s[8].split('transcript_name')[1].split(';')[0].gsub('"','').strip
      end

      feature_id = s[8].split('gene_id')[1].split(';')[0].gsub('"','').strip
      if feature_type == 'transcript' && line.include?('transcript_id')
        # update feature id to transcript_id
        feature_id = s[8].split('transcript_id')[1].split(';')[0].gsub('"','').strip
      end
      if feature_type == 'exon' && line.include?('exon_id')
        # update feature id to exon_id
        feature_id = s[8].split('exon_id')[1].split(';')[0].gsub('"','').strip
        $exon_id_2_gene_id[feature_id] = s[8].split('gene_id')[1].split(';')[0].gsub('"','').strip
      end
      
      feature_biotype = 'NA'
      if line.include?('gene_biotype')
        feature_biotype = s[8].split('gene_biotype')[1].split(';')[0].gsub('"','').strip
      end
      if feature_type == 'transcript' && line.include?('transcript_biotype')
        # update feature biotype to transcript_biotype
        feature_biotype = s[8].split('transcript_biotype')[1].split(';')[0].gsub('"','').strip
      end
      
      chr = s[0]
      start = s[3]
      stop = s[4]
      strand = s[6]
      $id2name[feature_id] = feature_name
      $id2biotype[feature_id] = feature_biotype
      $id2pos[feature_id] = [chr, start, stop, strand]
    end
    gtf.close
    puts "read in #{$id2name.keys.size} genes."

    if $add_plots
      # add plot HTML code and then give this updated file to the refactor function
      add_plot_html_code(html_path, pvalue)
      refactor_deseq_html_table(html_path.sub('.html','.html.tmp'))
      `rm #{html_path}.tmp`
    else
      refactor_deseq_html_table(html_path)
    end
  end
  
  def add_plot_html_code(html_path, pvalue)

    pvalue_label = 'full'
    if pvalue != '1.1'
      pvalue_label = "p#{pvalue}"
    end

    html_file = File.open(html_path,'r')    
    html_file_tmp = File.open(html_path.sub('.html','.html.tmp'),'w')

    html_file.each do |line|
      if line.start_with?('<div class="container"')
        tmp_array = line.split('</tr>')

        html_file_tmp << refac_table_header_plots(tmp_array[0], 1) << '</tr>' # first header
        html_file_tmp << refac_table_header_plots(tmp_array[1], 2) << '</tr>' # second header

        tmp_array[2..tmp_array.length-3].each do |row|
          row_splitted = row.split('</td>')
          gene_id = row_splitted[0].split('"">')[1]
          new_row = [row_splitted[0], "<td class=\"\"><a href=\"figuresRNAseq_analysis_with_DESeq2_#{pvalue_label}/boxplot.#{gene_id}.pdf\"><img border=\"0\" src=\"figuresRNAseq_analysis_with_DESeq2_#{pvalue_label}/mini.#{gene_id}.png\" alt=\"figuresRNAseq_analysis_with_DESeq2_#{pvalue_label}/mini.#{gene_id}.png\" /></a>", row_splitted[1], row_splitted[2], row_splitted[3]].join('</td>') << '</td>'            
          html_file_tmp << new_row << '</tr>'  
        end
        table_footer = tmp_array[tmp_array.length-2]
        html_file_tmp << refac_table_header_plots(table_footer, 3) << '</tr>' # table footer
        html_file_tmp << tmp_array[tmp_array.length-1] # footer
      else
        html_file_tmp << line
      end
    end
    html_file.close; html_file_tmp.close

  end
  
  def refactor_deseq_html_table(html_path)
    
    html_file = File.open(html_path,'r')    
    html_file_refac = File.open(html_path.sub('.tmp','').sub('.html','_extended.html'),'w')

    #pvalue = File.basename(html_path, '.html').split('_').reverse[0]

    html_file.each do |line|
      if line.start_with?('<div class="container"')
        tmp_array = line.split('</tr>')

        html_file_refac << refac_table_header(tmp_array[0], 1) << '</tr>' # first header
        html_file_refac << refac_table_header(tmp_array[1], 2) << '</tr>' # second header
        tmp_array[2..tmp_array.length-3].each do |row|
          row_splitted = row.sub('<a href','<a target="_blank" href').split('</td>')
          if $scan_feature_id_pattern
            feature_id = row_splitted[0].scan(/#{$scan_feature_id_pattern}/)[0]
          else
            feature_id = row_splitted[0].split('"">')[1]
          end
          next unless feature_id
          feature_id = feature_id.gsub('"','')
          feature_name = $id2name[feature_id]
          gene_biotype = $id2biotype[feature_id]
          #puts feature_id          
          pos_part = "<td class=\"\">#{$id2pos[feature_id][0]}:#{$id2pos[feature_id][1]}-#{$id2pos[feature_id][2]} (#{$id2pos[feature_id][3]})"
          if $ensembl_url
            if $exon_id_2_gene_id[feature_id]
              # in this case we write the exon gene ID but want to point to the ENSEMBL gene URL
              new_row = [row_splitted[0].sub('<td class="">',"<td class=\"\"><a target=\"_blank\" href=\"#{$ensembl_url}#{$exon_id_2_gene_id[feature_id]};\">") + '</a>', "<td class=\"\">#{feature_name}", "<td class=\"\">#{gene_biotype}", pos_part, row_splitted[1].sub('href=','target="_blank" href=').sub('<td class="">','<td class=""><div style="width: 200px">') + '</div>', row_splitted[2], row_splitted[3], row_splitted[4]].join('</td>') << '</td>'
            else
              new_row = [row_splitted[0].sub('<td class="">',"<td class=\"\"><a target=\"_blank\" href=\"#{$ensembl_url}#{feature_id};\">") + '</a>', "<td class=\"\">#{feature_name}", "<td class=\"\">#{gene_biotype}", pos_part, row_splitted[1].sub('href=','target="_blank" href=').sub('<td class="">','<td class=""><div style="width: 200px">') + '</div>', row_splitted[2], row_splitted[3], row_splitted[4]].join('</td>') << '</td>'
            end
	        else
            new_row = [row_splitted[0], "<td class=\"\">#{feature_name}", "<td class=\"\">#{gene_biotype}", pos_part, row_splitted[1].sub('href=','target="_blank" href=').sub('<td class="">','<td class=""><div style="width: 200px">') + '</div>', row_splitted[2], row_splitted[3], row_splitted[4]].join('</td>') << '</td>'            
          end          
          html_file_refac << new_row << '</tr>'  
        end
        table_footer = tmp_array[tmp_array.length-2]
        html_file_refac << refac_table_header(table_footer, 3) << '</tr>' # table footer
        html_file_refac << tmp_array[tmp_array.length-1] # footer
      else
        html_file_refac << line
      end
    end
    html_file.close; html_file_refac.close
  end


  def refac_table_header_plots(string, type)    
    split = string.split('</th>')    
    case type
      when 1
        [split[0], "<th class=\"sort-off top-header-row no-print\">Image", split[1], split[2], split[3]].join('</th>') << '</th>'
      when 2
        [split[0], "<th class=\"sort-off bottom-header-row\">Image", split[1], split[2], split[3]].join('</th>') << '</th>'
      else
        [split[0], "<th class=\"sort-off bottom-header-row\">Image", split[1], split[2], split[3]].join('</th>') << '</th>'
    end
  end

  def refac_table_header(string, type)    
    split = string.split('</th>')    
    case type
      when 1
        [split[0], "<th class=\" sort-string-robust top-header-row no-print\">Name", "<th class=\" sort-string-robust top-header-row no-print\">Type", "<th class=\" sort-string-robust top-header-row no-print\">Position", split[1], split[2], split[3], split[4]].join('</th>') << '</th>'
      when 2
        [split[0], "<th class=\" sort-string-robust bottom-header-row\">Name", "<th class=\" sort-string-robust bottom-header-row\">Type", "<th class=\" sort-string-robust bottom-header-row\">Position", split[1], split[2], split[3], split[4]].join('</th>') << '</th>'
      else
        [split[0], "<th class=\"sort-string-robust bottom-header-row\">Name", "<th class=\"sort-string-robust bottom-header-row\">Type", "<th class=\"sort-string-robust bottom-header-row\">Position", split[1], split[2], split[3], split[4]].join('</th>') << '</th>'
    end
  end

end

RefactorReportingtoolsTable.new(ARGV[0], ARGV[1], ARGV[2], ARGV[3])
