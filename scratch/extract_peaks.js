const { spawn } = require('child_process');
const ffmpegStatic = require('ffmpeg-static');

const inputFile = '/Users/rohitdudi/youtube/34_iran_history/a_rolls/Movie on 06-04-26 at 13.37.mov';

const ffmpegPath = ffmpegStatic;

console.log("Using ffmpeg:", ffmpegPath);

const ffmpeg = spawn(ffmpegPath, [
  '-i', inputFile,
  '-ac', '1',
  '-ar', '100', // 100 samples per second
  '-f', 's16le',
  '-'
]);

let totalSamples = 0;
let peaks = [];

ffmpeg.stdout.on('data', (chunk) => {
  for (let i = 0; i < chunk.length - 1; i += 2) {
    const val = chunk.readInt16LE(i);
    peaks.push(Math.abs(val / 32768));
    totalSamples++;
  }
});

ffmpeg.on('close', (code) => {
  console.log(`Finished. Extracted ${totalSamples} samples. Code: ${code}`);
  console.log(`First 10 peaks:`, peaks.slice(0, 10));
  
  // Downsample to simulate zoom level (e.g. max peak every 10 samples)
  const reduced = [];
  for (let i=0; i < peaks.length; i+=10) {
    reduced.push(Math.max(...peaks.slice(i, i+10)));
  }
  console.log(`Reduced length:`, reduced.length);
});
