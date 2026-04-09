$file1 = "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\text_encoders\qwen_3_4b.safetensors"
$file2 = "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\text_encoders\FLUX2\qwen_3_4b.safetensors"

(Get-FileHash $file1).Hash
(Get-FileHash $file2).Hash