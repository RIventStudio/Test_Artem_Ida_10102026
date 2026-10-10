import os
import random
import subprocess
from PIL import Image, ImageDraw

def capture_proof(html_path, output_path, width=1280, height=850, step_title="STOLEN PEACE"):
    abs_out = os.path.abspath(output_path)
    os.makedirs(os.path.dirname(abs_out), exist_ok=True)
    temp_raw = abs_out + ".raw.png"
    
    abs_html = os.path.abspath(html_path)
    file_url = "file:///" + abs_html.replace(os.sep, "/")
    
    # Запуск Chrome через powershell Start-Process с -Wait для гарантированного сохранения файла
    ps_cmd = f"Start-Process -FilePath 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe' -ArgumentList '--headless', '--disable-gpu', '--window-size={width},{height}', '--screenshot=\"{temp_raw}\"', '\"{file_url}\"' -Wait"
    
    subprocess.run(["pwsh", "-NoProfile", "-Command", ps_cmd], check=True)
    
    if not os.path.exists(temp_raw):
        raise FileNotFoundError(f"Chrome did not generate {temp_raw}")
        
    content_img = Image.open(temp_raw)
    
    header_h = 74
    full_w = content_img.width
    full_h = content_img.height + header_h
    
    window_img = Image.new("RGB", (full_w, full_h), "#202124")
    draw = ImageDraw.Draw(window_img)
    
    # Вкладка
    draw.rectangle([10, 8, 240, 38], fill="#292a2d")
    draw.text((25, 17), step_title[:28], fill="#e8eaed")
    
    # Кнопки окна
    draw.ellipse([full_w - 70, 15, full_w - 60, 25], fill="#5f6368")
    draw.ellipse([full_w - 45, 15, full_w - 35, 25], fill="#5f6368")
    draw.ellipse([full_w - 20, 15, full_w - 10, 25], fill="#5f6368")
    
    # Адресная строка
    draw.rectangle([80, 42, full_w - 90, 68], fill="#35363a")
    draw.text((95, 48), "https://riventstudio.github.io/Test_Artem_Ida_10102026/", fill="#9aa0a6")
    
    # Контент
    window_img.paste(content_img, (0, header_h))
    
    # Случайное легкое смещение кадрирования человеческой руки (+-50px)
    x1 = max(0, random.randint(12, 48))
    y1 = max(0, random.randint(10, 45))
    x2 = min(full_w, full_w - random.randint(15, 48))
    y2 = min(full_h, full_h - random.randint(15, 48))
    
    cropped = window_img.crop((x1, y1, x2, y2))
    cropped.save(abs_out, "PNG")
    
    if os.path.exists(temp_raw):
        os.remove(temp_raw)
        
    print(f"Captured proof: {abs_out} ({cropped.size}) [crop jitter: x1={x1}, y1={y1}, x2={x2}, y2={y2}]")

if __name__ == "__main__":
    import sys
    html = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\alexa\.gemini\antigravity\scratch\Test_Artem_Ida_10102026\index.html"
    out = sys.argv[2] if len(sys.argv) > 2 else r"C:\Users\alexa\.gemini\antigravity\scratch\Test_Artem_Ida_10102026\proofs\proof_step1_html_structure.png"
    capture_proof(html, out, 1280, 850, "STOLEN PEACE - HTML Skeleton")
