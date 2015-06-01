describe(
  'The jet (global) module',
  function()
    local jet
    it(
      'can be required',
      function()
        assert.has.no.errors(
          function()
            jet = require'jet'
          end)
      end)
    
    it(
      'jet.daemon is exposed',
      function()
        assert.is.equal(jet.daemon,require'jet.daemon')
        assert.is.equal(type(jet.daemon.new),'function')
      end)
    
    it(
      'jet.peer is exposed',
      function()
        assert.is.equal(jet.peer,require'jet.peer')
        assert.is.equal(type(jet.peer.new),'function')
        assert.is.same(jet.peer.new,require'jet.peer'.new)
      end)
    
    it(
      'jet.new equals jet.peer.new',
      function()
        assert.is.same(jet.new,require'jet.peer'.new)
      end)
    
  end)
