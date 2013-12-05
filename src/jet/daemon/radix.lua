local pairs = pairs
local print = print
local next = next
local type = type

new = function()
  local j = {}
  local radix_tree = {}
  local radix_elements = {}
  local return_tree = {}
  local lookup_fsm
  local root_lookup
  local leaf_lookup
  local radix_traverse
  local root_leaf_lookup
  local root_anypos_lookup
  
  
  lookup_fsm = function (wordpart, next_state, next_letter)
    if (wordpart:sub(next_state,next_state) ~= next_letter) then
      return false, 0
    end
    if (wordpart:len() == next_state) then
      return true, next_state
    else
      return false, next_state
    end
  end
  
  root_lookup = function( tree_instance, part, traverse, tree)
    if part:len() < 1 then
      if (traverse) then
        radix_traverse( tree_instance )
      else
        return_tree = tree_instance
      end
    else
      local s = part:sub( 1, 1 )
      if type(tree_instance[s])=="table" then
        root_lookup( tree_instance[s], part:sub(2), traverse)
      end
    end
  end
  
  leaf_lookup = function( tree_instance, word, state, only_end, traverse)
    local next_state = state+1
    for k, v in pairs(tree_instance) do
      if type(v)=="table" then
        local hit, next_state = lookup_fsm(word, next_state, k)
        if (hit == true) then
          if only_end then
            if type(v[next(v)])=="boolean" then
              radix_elements[next(v)] = true
            end
          else
            if traverse then
              radix_traverse( v )
            else
              table.insert(return_tree, v)
            end
          end
        else
          leaf_lookup( v, word, next_state, only_end, traverse);
        end
      end
    end
  end
  
  local add_to_tree
  add_to_tree = function( tree_instance, fullword, part )
    part = part or fullword;
    if part:len() < 1 then
      tree_instance[fullword]=true;
    else
      local s = part:sub( 1, 1 )
      if type(tree_instance[s])~="table" then
        tree_instance[s] = {};
      end
      add_to_tree( tree_instance[s], fullword, part:sub(2) )
    end
  end
  
  local remove_from_tree
  remove_from_tree = function( tree_instance, fullword, part )
    part = part or fullword;
    if part:len() < 1 then
      tree_instance[fullword]=nil;
    else
      local s = part:sub( 1, 1 )
      if type(tree_instance[s])~="table" then
        return
      end
      remove_from_tree( tree_instance[s], fullword, part:sub(2) )
    end
  end
  
  
  radix_traverse = function( tree_instance )
    for k, v in pairs(tree_instance) do
      if type(v)=="boolean" then
        radix_elements[k] = true
      elseif type(v)=="table" then
        radix_traverse( v );
      end
    end
  end
  
  local match_parts
  match_parts = function (tree_instance, parts)
    if (parts['equals']) then
      return_tree = {}
      root_lookup(tree_instance, parts['equals'], false)
      if type(return_tree[next(return_tree)])=="boolean" then
        radix_elements[next(return_tree)] = true
      end
    else
      local temp_tree = tree_instance
      if (parts['startsWith']) then
        return_tree = {}
        root_lookup(temp_tree, parts['startsWith'], false)
        temp_tree = return_tree
      end
      if (parts['contains']) then
        return_tree = {}
        leaf_lookup(temp_tree, parts['contains'], 0, false, false)
        temp_tree = return_tree
      end
      if (parts['endsWith']) then
        return_tree = {}
        leaf_lookup(temp_tree, parts['endsWith'], 0, true, false)
        temp_tree = return_tree
      end
      if temp_tree then
        radix_traverse(temp_tree)
      end
    end
  end
  
  j.add = add_to_tree
  j.add_main = function (word)
    add_to_tree(radix_tree, word)
  end
  j.remove = remove_from_tree
  j.remove_main = function (word)
    remove_from_tree(radix_tree, word)
  end
  j.traverse = radix_traverse
  j.traverse_main = function ()
    radix_traverse(radix_tree)
  end
  j.root_lookup = root_lookup
  j.root_lookup_main = function (word)
    root_lookup(radix_tree, word, true)
  end
  j.leaf_lookup = leaf_lookup
  j.leaf_lookup_main = function (word)
    leaf_lookup(radix_tree, word, 0, true, true)
  end
  j.anypos_lookup_main = function (word)
    leaf_lookup(radix_tree, word, 0, false, true)
  end
  j.reset_elements = function ()
    for k,v in pairs(radix_elements) do radix_elements[k]=nil end
  end
  j.reset_tree = function ()
    for k,v in pairs(radix_tree) do radix_tree[k]=nil end
  end
  j.match_parts = match_parts
  j.match_parts_main = function(parts)
    match_parts(radix_tree, parts)
  end
  j.found_elements = radix_elements
  j.tree = radix_tree
  
  return j
end

return {
  new = new
}
