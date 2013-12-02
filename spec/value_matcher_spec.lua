local vm = require'jet.daemon.value_matcher'

describe(
  'The jet.daemon.value_matcher module',
  function()
    
    describe('Internal tests',function()
        it('access_field works one level deep',function()
            local t = {}
            local b = {}
            t.a = b
            local accessor = vm._access_field('a')
            assert.is_equal(t.a,accessor(t))
            assert.is_nil(accessor({}))
          end)
        
        it('access_field works two level deep',function()
            local t = {}
            local b = {}
            t.a = {
              xx = b
            }
            local accessor = vm._access_field('a.xx')
            assert.is_equal(t.a.xx,accessor(t))
            t.a = nil
            local ok = pcall(accessor,t)
            assert.is_false(ok)
          end)
        
      end)
    
  end)
