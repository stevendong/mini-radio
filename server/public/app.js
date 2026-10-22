const find = id => document.getElementById(id);
const status = find('status');
find('create').addEventListener('click', async () => {
  const invitation = find('invitation').value.trim();
  if (!/^MRI_[A-Za-z0-9_-]{43}$/.test(invitation)) { status.textContent = '请输入完整的一次性邀请码。已有同步密钥无需重新生成。'; return; }
  find('create').disabled = true; status.textContent = '正在创建…';
  try {
    const response = await fetch('/v1/keys', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ invitation }), cache: 'no-store', credentials: 'omit' });
    if (!response.ok) throw new Error(response.status === 403 ? '邀请码无效、已使用或已过期。' : response.status === 429 ? '申请过于频繁，请稍后重试。' : '暂时无法创建，请稍后重试。');
    const data = await response.json();
    if (!/^MR1_[A-Za-z0-9_-]{43}$/.test(data.key)) throw new Error('服务返回格式异常，请稍后重试。');
    find('key').value = data.key; find('credential').hidden = false;
    find('invitation').value = ''; find('invitation').disabled = true;
    find('create').hidden = true; status.textContent = '已创建。请保存密钥，再连接你的设备。';
  } catch (error) { status.textContent = error.message; find('create').disabled = false; }
});
find('copy').addEventListener('click', async () => {
  try { await navigator.clipboard.writeText(find('key').value); status.textContent = '已复制密钥，请私下保存。'; }
  catch { status.textContent = '无法访问剪贴板，请点击“显示”后手动复制。'; }
});
find('reveal').addEventListener('click', () => {
  const visible = find('key').type === 'password';
  find('key').type = visible ? 'text' : 'password'; find('reveal').textContent = visible ? '隐藏' : '显示';
});
find('revoke').addEventListener('click', async () => {
  const key = find('revoke-key').value.trim(), message = find('revoke-status');
  if (!/^MR1_[A-Za-z0-9_-]{43}$/.test(key)) { message.textContent = '请输入完整的同步密钥。'; return; }
  if (!confirm('停用这把密钥并删除云端数据？所有设备将无法再用它同步。本地副本保留。')) return;
  find('revoke').disabled = true;
  try {
    const response = await fetch('/v1/library', { method: 'DELETE', headers: { Authorization: 'Bearer ' + key }, cache: 'no-store', credentials: 'omit' });
    if (!response.ok) throw new Error(response.status === 401 ? '密钥无效或已经停用。' : '暂时无法删除，请稍后重试。');
    find('revoke-key').value = ''; message.textContent = '云端数据已删除，密钥已失效。本地数据保留。';
    if (find('key').value === key) {
      find('key').value = ''; find('credential').hidden = true;
      find('create').hidden = false; find('create').disabled = false; find('invitation').disabled = false;
      status.textContent = '此空间已删除。新建空间需要新的邀请码。';
    }
  } catch (error) { message.textContent = error.message; }
  finally { find('revoke').disabled = false; }
});
window.addEventListener('pagehide', () => { find('key').value = ''; find('revoke-key').value = ''; find('invitation').value = ''; find('credential').hidden = true; });
window.addEventListener('pageshow', event => {
  if (event.persisted) { find('create').hidden = false; find('create').disabled = false; find('invitation').disabled = false; status.textContent = ''; }
});
