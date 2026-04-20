import { parentPort, workerData } from 'worker_threads';
import fs from 'fs';

interface WorkerData {
  wavPath: string;
  modelId: string;
  language: string;
  modelsDir: string;
}

const { wavPath, modelId, language, modelsDir } = workerData as WorkerData;

/** Read a 16-bit PCM WAV file and return Float32Array of samples */
function readWavToFloat32(wavPath: string): Float32Array {
  const buf = fs.readFileSync(wavPath);
  let dataOffset = 12; // skip RIFF header
  while (dataOffset < buf.length - 8) {
    const chunkId = buf.toString('ascii', dataOffset, dataOffset + 4);
    const chunkSize = buf.readUInt32LE(dataOffset + 4);
    if (chunkId === 'data') {
      dataOffset += 8;
      break;
    }
    dataOffset += 8 + chunkSize;
  }
  const samples = (buf.length - dataOffset) / 2;
  const float32 = new Float32Array(samples);
  for (let i = 0; i < samples; i++) {
    const int16 = buf.readInt16LE(dataOffset + i * 2);
    float32[i] = int16 / 32768.0;
  }
  return float32;
}

async function run() {
  try {
    // Dynamic import to bypass TS transpilation
    const { pipeline, env } = await new Function('return import("@xenova/transformers")')();
    env.cacheDir = modelsDir;
    env.allowLocalModels = true;

    // Load pipeline
    const pipe = await pipeline(
      'automatic-speech-recognition',
      modelId,
      {
        progress_callback: (info: { status: string }) => {
          if (info.status === 'loading') parentPort?.postMessage({ type: 'progress', progress: 20, status: 'Loading model…' });
          if (info.status === 'ready') parentPort?.postMessage({ type: 'progress', progress: 30, status: 'Model loaded, transcribing…' });
        },
      },
    );

    parentPort?.postMessage({ type: 'progress', progress: 30, status: 'Transcribing…' });

    const audioData = readWavToFloat32(wavPath);
    const isEnglishOnly = modelId.endsWith('.en');

    const inferenceOpts: Record<string, any> = {
      return_timestamps: 'word',
      chunk_length_s: 30,
      stride_length_s: 5,
      language: isEnglishOnly ? undefined : (language === 'auto' ? undefined : language),
      task: 'transcribe',
    };

    const output = await pipe(audioData, inferenceOpts);

    parentPort?.postMessage({ type: 'progress', progress: 90, status: 'Processing results…' });

    // Output is the raw pipeline result. The service will map it to TranscriptWords.
    parentPort?.postMessage({ type: 'done', output });
  } catch (err: any) {
    if (err.message === 'CANCELLED_BY_USER') {
      parentPort?.postMessage({ type: 'error', error: 'CANCELLED_BY_USER' });
    } else {
      parentPort?.postMessage({ type: 'error', error: err.message || String(err) });
    }
  }
}

run();
