package com.gennysophie.studio
data class GenerationRequest(val character:String,val prompt:String,val referenceUri:String?,val width:Int=512,val height:Int=512,val steps:Int=12,val seed:Long=0L)