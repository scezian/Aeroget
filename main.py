import asyncio
import json
import logging
import subprocess
import os
from typing import AsyncGenerator
import urllib.parse

from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from sse_starlette.sse import EventSourceResponse

app = FastAPI(title="AeroGet Backend")

# We mount static directory to serve index.html
import pathlib
static_dir = pathlib.Path(__file__).parent / "static"
if not static_dir.exists():
    static_dir.mkdir(parents=True, exist_ok=True)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("AeroGet")

@app.get("/api/info")
async def get_info(url: str):
    try:
        # Run yt-dlp to get JSON info
        cmd = ["yt-dlp", "-J", url]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        info = json.loads(result.stdout)
        
        # Filter formats
        formats = info.get("formats", [])
        
        # We want to categorize formats: Video+Audio, Video Only, Audio Only
        available_formats = []
        for f in formats:
            try:
                # Add a readable name
                resolution = f.get('resolution') or f.get('format_note') or 'Unknown'
                ext = f.get('ext', 'unknown')
                vcodec = f.get('vcodec', 'none')
                acodec = f.get('acodec', 'none')
                
                # Filter out useless ones
                if vcodec == 'none' and acodec == 'none':
                    continue
                
                has_video = vcodec != 'none'
                has_audio = acodec != 'none'
                
                type_str = "Video+Audio" if has_video and has_audio else ("Video Only" if has_video else "Audio Only")
                if has_video and not has_audio:
                    continue # Let yt-dlp handle merging, we won't expose video-only without audio to user to keep it simple, except if they want just audio
                
                label = f"{type_str} - {resolution} ({ext})"
                format_id = f.get('format_id')
                
                available_formats.append({
                    "id": format_id,
                    "label": label,
                    "type": type_str,
                    "resolution": resolution,
                    "ext": ext
                })
            except Exception:
                pass

        # Sort and deduplicate formats (basic logic: just provide a few good ones)
        return JSONResponse(content={
            "title": info.get("title", "Unknown Title"),
            "thumbnail": info.get("thumbnail"),
            "channel": info.get("uploader", "Unknown Uploader"),
            "duration": info.get("duration_string", ""),
            "formats": available_formats[-15:] # Take last 15 which are usually the best
        })
    except subprocess.CalledProcessError as e:
        logger.error(f"yt-dlp error: {e.stderr}")
        raise HTTPException(status_code=400, detail="Failed to parse URL. Ensure it is valid.")
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/browse")
async def browse_folder():
    try:
        # We use zenity to open a folder picker natively on Linux
        result = subprocess.run(["zenity", "--file-selection", "--directory"], capture_output=True, text=True)
        if result.returncode == 0:
            path = result.stdout.strip()
            return JSONResponse(content={"path": path})
        else:
            return JSONResponse(content={"path": ""})
    except Exception as e:
        logger.error(f"Browse error: {e}")
        return JSONResponse(content={"path": os.path.expanduser("~/Downloads")})

@app.get("/api/download")
async def download(request: Request, url: str, format: str = "best", path: str = ""):
    if not path:
        path = os.path.expanduser("~/Downloads")
        
    async def event_generator() -> AsyncGenerator[dict, None]:
        # yt-dlp command
        cmd = [
            "yt-dlp",
            "-f", format + "+bestaudio/best" if format != "best" else "bestvideo+bestaudio/best",
            "--newline",
            "-o", f"{path}/%(title)s.%(ext)s",
            url
        ]
        
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT
        )
        
        try:
            while True:
                if await request.is_disconnected():
                    process.terminate()
                    break
                    
                line = await process.stdout.readline()
                if not line:
                    break
                    
                line_str = line.decode('utf-8').strip()
                # Parse progress: [download]  15.2% of 100.0MiB at  1.2MiB/s ETA 01:23
                if "[download]" in line_str and "%" in line_str:
                    yield {"data": json.dumps({"type": "progress", "text": line_str})}
                else:
                    yield {"data": json.dumps({"type": "log", "text": line_str})}
                    
            await process.wait()
            yield {"data": json.dumps({"type": "complete", "text": "Download finished"})}
        except Exception as e:
            yield {"data": json.dumps({"type": "error", "text": str(e)})}
            process.terminate()
            
    return EventSourceResponse(event_generator())

app.mount("/", StaticFiles(directory="static", html=True), name="static")

def start_server():
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8000, log_level="error")

if __name__ == "__main__":
    import threading
    import webview
    import time
    
    t = threading.Thread(target=start_server, daemon=True)
    t.start()
    
    time.sleep(0.5)
    
    webview.create_window(
        'AeroGet Premium Downloader', 
        'http://127.0.0.1:8000',
        width=850, 
        height=850, 
        resizable=True,
        background_color='#0f111a'
    )
    webview.start()
