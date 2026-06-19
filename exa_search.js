const http = require('http');

const query = "category:research paper streak mechanics game engagement retention player behavior learning outcomes";
const numResults = 15;

const requestBody = JSON.stringify({
  jsonrpc: "2.0",
  id: 1,
  method: "tools/call",
  params: {
    name: "web_search_exa",
    arguments: {
      query: query,
      numResults: numResults
    }
  }
});

const options = {
  hostname: 'mcp.exa.ai',
  port: 443,
  path: '/mcp',
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(requestBody)
  }
};

const https = require('https');
const req = https.request(options, (res) => {
  let data = '';
  res.on('data', (chunk) => {
    data += chunk;
  });
  res.on('end', () => {
    console.log(data);
  });
});

req.on('error', (error) => {
  console.error('Error:', error);
});

req.write(requestBody);
req.end();
