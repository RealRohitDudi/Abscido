const buffer = Buffer.from(new Float32Array([0.123, -0.456, 1.0]).buffer);
const base64 = buffer.toString('base64');
console.log("Base64:", base64);

const binStr = atob(base64);
const bytes = new Uint8Array(binStr.length);
for (let i = 0; i < binStr.length; i++) {
  bytes[i] = binStr.charCodeAt(i);
}
const floats = new Float32Array(bytes.buffer);
console.log("Floats:", floats);
