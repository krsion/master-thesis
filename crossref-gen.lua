function have_all_colons(elem)
    for i, citet in ipairs(elem.citations) do
        if string.find(citet.id, ":") == nil then
            return false
        end
    end
    return true
end

if FORMAT:match 'latex' then
    function Cite(elem)
        -- Transforming [@thm:1] or [@alg:1] into \cref{thm:1} or \cref{alg:1} instead of \cite{thm:1} or \cite{alg:1}
        -- This function is needed because pandoc-crossref doesn't recognize thm or alg
        if not have_all_colons(elem) then
            return elem
        end

        citations = {}
        final_id = ''
        for i, citet in ipairs(elem.citations) do
            count = 0
            for word in string.gmatch(citet.id, '([^:]+)') do
                count = count + 1
                if i == 1 and count == 1 then
                    if string.match(string.sub(word, 1, 1), "%u") then
                        final_id = '\\Cref{'
                    else
                        final_id = '\\cref{'
                    end
                end
                if count == 1 then
                    final_id = final_id .. string.lower(word)
                else
                    final_id = final_id .. ':' .. word
                end
            end
            final_id = final_id .. ','
        end
        final_id = final_id:sub(1, -2) -- remove the last comma
        final_id = final_id .. '}'
        table.insert(citations, pandoc.RawInline('latex', final_id))
        return citations
    end
end