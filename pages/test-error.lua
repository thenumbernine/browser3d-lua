local Page = {}
Page.title = 'test error'
function Page:init()
	error'here'
end
return Page
