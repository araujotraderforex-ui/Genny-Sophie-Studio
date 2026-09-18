package com.gennysophie.studio
object CharacterProfiles{
 const val GENNY="Gênny"
 const val SOPHIE="Sophie"
 fun identityPrompt(name:String)=when(name){SOPHIE->"adult synthetic woman, Sophie profile, preserve reference face and proportions";else->"adult synthetic woman, Gênny profile, preserve reference face and proportions"}
}