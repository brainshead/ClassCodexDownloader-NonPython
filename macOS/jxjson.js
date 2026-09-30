ObjC.import('Foundation');
function readFile(path) {
  const data = $.NSData.dataWithContentsOfFile(path);
  if (!data) throw new Error('Cannot read ' + path);
  return $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding).js;
}
function esc(s) {
  return encodeURIComponent(String(s)).replace(/%2F/gi, '/');
}
const mode = argv[0];
const path = argv[1];
const obj = JSON.parse(readFile(path));
if (mode === 'config') {
  console.log([obj.buildId || '', obj.manifestUrl || '', obj.manifestSha256 || ''].join('\t'));
} else if (mode === 'manifest') {
  const files = obj.files || [];
  for (const f of files) {
    console.log([f.path || '', f.size || '', f.sha256 || '', esc(f.path || '')].join('\t'));
  }
} else {
  throw new Error('Unknown mode');
}
