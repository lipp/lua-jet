local utils = require'jet.utils'

describe(
  'The jet.utils module',
  function()
    
    it('is_empty_table works',function()
        assert.is_true(utils.is_empty_table({}))
        assert.is_false(utils.is_empty_table({'asd'}))
        assert.is_false(utils.is_empty_table({a=123}))
      end)
    
    it('access_field works one level deep',function()
        local t = {}
        local b = {}
        t.a = b
        local accessor = utils.access_field('a')
        assert.is_equal(t.a,accessor(t))
        assert.is_nil(accessor({}))
      end)
    
    it('access_field works two level deep',function()
        local t = {}
        local b = {}
        t.a = {
          xx = b
        }
        local accessor = utils.access_field('a.xx')
        assert.is_equal(t.a.xx,accessor(t))
        t.a = nil
        local ok = pcall(accessor,t)
        assert.is_false(ok)
      end)
    
    
  end)

