function Expand-Template {
  param(
    [Parameter(Mandatory)][string]$TemplatePath,
    [Parameter(Mandatory)][hashtable]$Placeholders
  )

  $content = Get-Content -Raw -Path $TemplatePath
  foreach ($key in $Placeholders.Keys) {
    $content = $content.Replace("{{$key}}", $Placeholders[$key])
  }
  return $content
}
