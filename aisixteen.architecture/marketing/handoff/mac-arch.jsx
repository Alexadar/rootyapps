// Glue: composes the macos-window starter with the AISixteen Architecture sidebar.
function ArchMacWindow({ children }) {
  const row = (label, count, selected) => (
    <div key={label} style={{
      display: 'flex', justifyContent: 'space-between', alignItems: 'center',
      padding: '7px 10px', borderRadius: 9,
      background: selected ? 'rgba(180,85,45,0.12)' : 'transparent',
      fontFamily: '-apple-system, system-ui', fontSize: 13,
      fontWeight: selected ? 600 : 400, color: '#1D1A17',
    }}>
      <span>{label}</span>
      <span style={{ color: 'rgba(29,26,23,0.45)', fontWeight: 400 }}>{count}</span>
    </div>
  );
  const sidebar = (
    <div style={{ display: 'flex', flexDirection: 'column', flex: 1, minHeight: 0 }}>
      <MacSidebarHeader title="Spaces" />
      {row('Living room', '3', true)}
      {row('House facade', '2', false)}
      {row('Kitchen', '1', false)}
      <div style={{
        marginTop: 'auto', padding: '8px 10px', borderRadius: 9,
        fontFamily: '-apple-system, system-ui', fontSize: 11.5, lineHeight: 1.4,
        color: 'rgba(29,26,23,0.55)', background: 'rgba(29,26,23,0.05)',
      }}>Rendering: Japandi<br />step 18 of 32</div>
    </div>
  );
  return (
    <MacWindow width={900} height={590} title="AISixteen Architecture" sidebar={sidebar}>
      {children}
    </MacWindow>
  );
}
window.ArchMacWindow = ArchMacWindow;
