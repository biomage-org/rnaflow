process dammit {
    label 'dammit'

    if ( params.softlink_results ) { publishDir "${params.output}/${params.rnaseq_annotation_dir}/dammit/${params.uniref90_dir}", pattern: "*" }
    else { publishDir "${params.output}/${params.rnaseq_annotation_dir}/dammit/${params.uniref90_dir}", mode: 'copy', pattern: "*" }

  input:
    path(transcriptome_assembly)
    path(busco_db)
    val(tool)

  output:
    tuple path("${tool}", type: 'dir'), path('uniprot_sprot_reduced.dat')

  script:
    """
    tar zxvf ${dbs}
    BUSCO=\$(echo ${params.busco_db} | awk 'BEGIN{FS="_"};{print \$1}')
    dammit annotate ${transcriptome_assembly} --database-dir \${PWD}/dbs --busco-group \${BUSCO} -n dammit -o ${tool} --n_threads ${task.cpus}
    cp dbs/uniprot_sprot_reduced.dat .
    """
  }

