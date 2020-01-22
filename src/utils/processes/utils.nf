nextflow.preview.dsl=2

import java.nio.file.Paths

if(!params.containsKey("test")) {
	binDir = "${workflow.projectDir}/src/utils/bin/"
} else {
	binDir = ""
}

def detectCellRangerVersionData(cellRangerV2Data, cellRangerV3Data) {
	if(cellRangerV2Data.isDirectory()) {
		if(cellRangerV2Data.exists()) {
			genomes = cellRangerV2Data.list()
			if(genomes.size() > 1 || genomes.size() == 0)
				throw new Exception("None or multiple genomes detected for the output generated by CellRanger v2. Selecting custom genome is currently not implemented.")
			return file(Paths.get(cellRangerV2Data.toString(), genomes[0]))
		} else if(cellRangerV3Data.exists())
			return cellRangerV3Data
		throw new Exception("Cannot detect the version of the data format of CellRanger.")
	} else {
		if(cellRangerV2Data.exists()) {
			return cellRangerV2Data
		} else if(cellRangerV3Data.exists())
			return cellRangerV3Data
		throw new Exception("Cannot detect the version of the data format of CellRanger.")
	}
}

process SC__FILE_CONVERTER {

    echo true
	cache 'deep'
	container params.sc.scanpy.container
	clusterOptions "-l nodes=1:ppn=2 -l pmem=30gb -l walltime=1:00:00 -A ${params.global.qsubaccount}"
	publishDir "${params.global.outdir}/data/intermediate", mode: 'symlink', overwrite: true

	input:
		tuple val(sampleId), path(f)

	output:
		tuple val(sampleId), path("${sampleId}.SC__FILE_CONVERTER.${processParams.off}")

	script:
		def sampleParams = params.parseConfig(sampleId, params.global, params.sc.file_converter)
		processParams = sampleParams.local

		switch(processParams.iff) {
			case "10x_cellranger_mex":
				// Reference: https://kb.10xgenomics.com/hc/en-us/articles/115000794686-How-is-the-MEX-format-used-for-the-gene-barcode-matrices-
				// Check if output was generated with CellRanger v2 or v3
				cellranger_outs_v2_mex = file("${f.toRealPath()}/${processParams.useFilteredMatrix ? "filtered" : "raw"}_gene_bc_matrices/")
				cellranger_outs_v3_mex = file("${f.toRealPath()}/${processParams.useFilteredMatrix ? "filtered" : "raw"}_feature_bc_matrix/")
				f = detectCellRangerVersionData(cellranger_outs_v2_mex, cellranger_outs_v3_mex)
			break;

			case "10x_cellranger_h5":
				// Check if output was generated with CellRanger v2 or v3
				cellranger_outs_v2_h5 = file("${f.toRealPath()}/${processParams.useFilteredMatrix ? "filtered" : "raw"}_gene_bc_matrices.h5")
				cellranger_outs_v3_h5 = file("${f.toRealPath()}/${processParams.useFilteredMatrix ? "filtered" : "raw"}_feature_bc_matrix.h5")
				f = detectCellRangerVersionData(cellranger_outs_v2_h5, cellranger_outs_v3_h5)
			break;

			case "csv":
				// Nothing to be done here
			break;

			case "tsv":
				// Nothing to be done here
			break;

			case "h5ad":
				// Nothing to be done here
			break;
			
			default:
				throw new Exception("The given input format ${processParams.iff} is not recognized.")
			break;
		}

		if(processParams.iff == "h5ad")
			"""
			cp ${f} "${sampleId}.SC__FILE_CONVERTER.h5ad"
			"""
		else
			"""
			${binDir}sc_file_converter.py \
				--sample-id "${sampleId}" \
				${(processParams.containsKey('tagCellWithSampleId')) ? '--tag-cell-with-sample-id' : ''} \
				--input-format $processParams.iff \
				--output-format $processParams.off \
				${f} \
				"${sampleId}.SC__FILE_CONVERTER.${processParams.off}"
			"""

}

process SC__FILE_CONVERTER_HELP {

	container params.sc.scanpy.container

	output:
		stdout()

	script:
		"""
		${binDir}sc_file_converter.py -h | awk '/-h/{y=1;next}y'
		"""

}

process SC__FILE_CONCATENATOR() {

	cache 'deep'
	container params.sc.scanpy.container
	clusterOptions "-l nodes=1:ppn=2 -l pmem=30gb -l walltime=1:00:00 -A ${params.global.qsubaccount}"
	publishDir "${params.global.outdir}/data/intermediate", mode: 'symlink', overwrite: true

	input:
		file("*")

	output:
		tuple val(params.global.project_name), path("${params.global.project_name}.SC__FILE_CONCATENATOR.${processParams.off}")

	script:
		processParams = params.sc.file_concatenator
		"""
		${binDir}sc_file_concatenator.py \
			--file-format $processParams.off \
			${(processParams.containsKey('join')) ? '--join ' + processParams.join : ''} \
			--output "${params.global.project_name}.SC__FILE_CONCATENATOR.${processParams.off}" *
		"""

}

process SC__STAR_CONCATENATOR() {

	container params.sc.scanpy.container
	clusterOptions "-l nodes=1:ppn=2 -l pmem=30gb -l walltime=1:00:00 -A ${params.global.qsubaccount}"
	publishDir "${params.global.outdir}/data/intermediate", mode: 'symlink', overwrite: true

	input:
		tuple val(sampleId), path(f)

	output:
		tuple val(sampleId), path("${params.global.project_name}.SC__STAR_CONCATENATOR.${processParams.off}")

	script:
		def sampleParams = params.parseConfig(sampleId, params.global, params.sc.star_concatenator)
		processParams = sampleParams.local
		id = params.global.project_name
		"""
		${binDir}sc_star_concatenator.py \
			--stranded ${processParams.stranded} \
			--output "${params.global.project_name}.SC__STAR_CONCATENATOR.${processParams.off}" $f
		"""

}

process SC__PUBLISH_H5AD {

    clusterOptions "-l nodes=1:ppn=2 -l pmem=30gb -l walltime=1:00:00 -A ${params.global.qsubaccount}"
	publishDir "${params.global.outdir}/data", mode: 'link', overwrite: true, saveAs: { filename -> "${tag}.${fOutSuffix}.h5ad" }
	

    input:
		tuple val(tag), path(f)
		val(fOutSuffix)

    output:
    	tuple val(tag), path(f)

	script:
		"""
		"""

}

process COMPRESS_HDF5() {

	container "aertslab/sctx-hdf5:1.10.5-r2"
	clusterOptions "-l nodes=1:ppn=2 -l pmem=30gb -l walltime=1:00:00 -A ${params.global.qsubaccount}"
	publishDir "${params.global.outdir}/loom", mode: 'link', overwrite: true

	input:
		tuple val(id), path(f)

	output:
		tuple val(id), path("${id}.COMPRESS_HDF5.${f.extension}")

	shell:
		"""
		GZIP_COMPRESSION_LEVEL=6
		h5repack \
		   -v \
		   -f GZIP=\${GZIP_COMPRESSION_LEVEL} \
		   $f \
		   "${id}.COMPRESS_HDF5.${f.extension}"
		"""

}
