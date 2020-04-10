nextflow.preview.dsl=2

import static groovy.json.JsonOutput.*

//////////////////////////////////////////////////////
//  process imports:

// Imports

//////////////////////////////////////////////////////
//  Define the workflow 

workflow COMBINE_BY_PARAMS {

    take:
        // Expects (sampleId, data, unstashedParams)
        A
        // Expects (sampleId, data, [stashedParams])
        B
        params

    main:
        if(params != null && params.isParameterExplorationModeOn()) {
            out = A.concat(
                B.map { it -> tuple(it[0], it[1], *it[2]) } // Unstash params
            ).map {
                it -> tuple(it[2..(it.size()-1)], it[0], it[1]) // Stash params
            }.groupTuple(
                by: [0, params.numParams()-1]
            ).map { 
                it -> tuple(it[1], *it[2], it[0]) 
            }
        } else {
            out = A.join(B)
        }

    emit:
        out

}

def INIT() {

    def paramsCopy = params.findAll({!["parseConfig", "parse-config"].contains(it.key)})
    params.misc.manifestAsJSON = toJson(workflow.manifest)
    params.misc.paramsAsJSON = toJson(paramsCopy)

    if(!params.global.containsKey('seed')) {
        params.global.seed = workflow.manifest.version.replaceAll("\\.","").toInteger()

        Channel.from('').view {
                """
------------------------------------------------------------------
\u001B[32m No seed detected in the config \u001B[0m
\u001B[32m To ensure reproducibility the seed has been set to ${params.global.seed} \u001B[0m
------------------------------------------------------------------
                """
        }
    } else {
        Channel.from('').view {
                """
------------------------------------------------------------------
\u001B[32m Custom seed detected in the config \u001B[0m
\u001B[32m Seed is set to ${params.global.seed} \u001B[0m
------------------------------------------------------------------
                """
        }
    }

}
