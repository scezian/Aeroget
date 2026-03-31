document.addEventListener('DOMContentLoaded', () => {
    const urlInput = document.getElementById('url-input');
    const pasteBtn = document.getElementById('paste-btn');
    const fetchBtn = document.getElementById('fetch-btn');
    const loading = document.getElementById('loading');
    
    const resultSection = document.getElementById('result-section');
    const mediaThumb = document.getElementById('media-thumb');
    const mediaTitle = document.getElementById('media-title');
    const mediaChannel = document.getElementById('media-channel');
    const mediaDuration = document.getElementById('media-duration');
    const formatSelect = document.getElementById('format-select');
    const directoryInput = document.getElementById('directory-input');
    const browseBtn = document.getElementById('browse-btn');
    const downloadBtn = document.getElementById('download-btn');
    
    const progressContainer = document.getElementById('progress-container');
    const progressBarFill = document.getElementById('progress-bar-fill');
    const progressPercent = document.getElementById('progress-percent');
    const progressEta = document.getElementById('progress-eta');
    const progressSpeed = document.getElementById('progress-speed');
    const statusText = document.getElementById('status-text');

    let isDownloading = false;

    // Smart Paste
    pasteBtn.addEventListener('click', async () => {
        try {
            const text = await navigator.clipboard.readText();
            if (text) {
                urlInput.value = text;
                fetchInfo(text);
            }
        } catch (err) {
            alert('Failed to read clipboard contents.');
        }
    });

    fetchBtn.addEventListener('click', () => {
        const url = urlInput.value.trim();
        if (url) fetchInfo(url);
    });

    urlInput.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') fetchBtn.click();
    });

    // Browse Folder natively
    browseBtn.addEventListener('click', async () => {
        try {
            const res = await fetch('/api/browse');
            const data = await res.json();
            if (data.path) {
                directoryInput.value = data.path;
            }
        } catch (err) {
            console.error('Failed to browse', err);
        }
    });

    async function fetchInfo(url) {
        if (isDownloading) return;
        
        loading.classList.remove('hidden');
        resultSection.classList.add('hidden');
        progressContainer.classList.add('hidden');
        
        try {
            const res = await fetch(`/api/info?url=${encodeURIComponent(url)}`);
            if (!res.ok) throw new Error(await res.text());
            
            const data = await res.json();
            
            mediaThumb.src = data.thumbnail || 'https://via.placeholder.com/200';
            mediaTitle.textContent = data.title;
            mediaChannel.textContent = data.channel;
            mediaDuration.textContent = data.duration || 'Unknown';
            
            // Populate formats
            formatSelect.innerHTML = '<option value="best">Best Available (Auto)</option>';
            data.formats.forEach(f => {
                const opt = document.createElement('option');
                opt.value = f.id || 'best';
                opt.textContent = f.label;
                formatSelect.appendChild(opt);
            });

            // Try to set default path to ~/Downloads if empty
            if (!directoryInput.value) {
                directoryInput.value = '~/Downloads';
            }
            
            loading.classList.add('hidden');
            resultSection.classList.remove('hidden');
            
            // Subtle animation
            resultSection.style.opacity = '0';
            resultSection.style.transform = 'translateY(20px)';
            setTimeout(() => {
                resultSection.style.transition = 'all 0.5s ease';
                resultSection.style.opacity = '1';
                resultSection.style.transform = 'translateY(0)';
            }, 50);

        } catch (err) {
            alert('Failed to analyze URL: ' + err.message);
            loading.classList.add('hidden');
        }
    }

    // Start Download using SSE
    downloadBtn.addEventListener('click', () => {
        if (isDownloading) return;
        
        const url = urlInput.value.trim();
        const format = formatSelect.value;
        const path = directoryInput.value;
        
        if (!url) return;
        
        isDownloading = true;
        downloadBtn.textContent = 'Downloading...';
        downloadBtn.style.opacity = '0.7';
        browseBtn.disabled = true;
        
        progressContainer.classList.remove('hidden');
        progressBarFill.style.width = '0%';
        progressPercent.textContent = '0%';
        progressEta.textContent = 'ETA: Calculating...';
        progressSpeed.textContent = '0.0MiB/s';
        statusText.textContent = 'Initializing engine...';
        
        // SSE Request
        const sseUrl = `/api/download?url=${encodeURIComponent(url)}&format=${encodeURIComponent(format)}&path=${encodeURIComponent(path)}`;
        const eventSource = new EventSource(sseUrl);
        
        eventSource.onmessage = (event) => {
            try {
                const data = JSON.parse(event.data);
                
                if (data.type === 'progress') {
                    // yt-dlp string: [download]  15.2% of 100.0MiB at  1.2MiB/s ETA 01:23
                    const text = data.text;
                    statusText.textContent = text;
                    
                    const pctMatch = text.match(/([0-9.]+)%/);
                    if (pctMatch) {
                        const pct = parseFloat(pctMatch[1]);
                        progressBarFill.style.width = `${pct}%`;
                        progressPercent.textContent = `${pct.toFixed(1)}%`;
                    }
                    
                    const speedMatch = text.match(/at\s+([0-9a-zA-Z./]+)/);
                    if (speedMatch) progressSpeed.textContent = speedMatch[1];
                    
                    const etaMatch = text.match(/ETA\s+([0-9:]+)/);
                    if (etaMatch) progressEta.textContent = `ETA: ${etaMatch[1]}`;
                    
                } else if (data.type === 'log') {
                    statusText.textContent = data.text;
                } else if (data.type === 'error') {
                    statusText.textContent = `Error: ${data.text}`;
                    statusText.style.color = '#ff4c4c';
                    finishDownload();
                    eventSource.close();
                } else if (data.type === 'complete') {
                    statusText.textContent = 'Download Complete! ✨';
                    progressBarFill.style.width = '100%';
                    progressPercent.textContent = '100%';
                    finishDownload(true);
                    eventSource.close();
                }
            } catch (e) {
                console.error('SSE Error:', e);
            }
        };
        
        eventSource.onerror = () => {
            statusText.textContent = 'Connection lost.';
            finishDownload();
            eventSource.close();
        };
    });
    
    function finishDownload(success = false) {
        isDownloading = false;
        downloadBtn.textContent = success ? 'Download Another' : 'Retry Download';
        downloadBtn.style.opacity = '1';
        browseBtn.disabled = false;
    }
});
