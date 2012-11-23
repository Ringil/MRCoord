require 'sinatra'
require 'data_mapper'
require 'json'

enable :sessions

SITE_TITLE = "Community MapReduce"
DataMapper.setup(:default, "sqlite3://#{Dir.pwd}/coord.db")
#DataMapper.setup(:default, ENV['DATABASE_URL'])

helpers do
	include Rack::Utils
	alias_method :h, :escape_html
end


######################################
#             Database Model         #
######################################
class Job
	include DataMapper::Resource
	property :id, 			Serial						#Job id
	property :desc, 		Text,	:required => true 	#Description of the job
	property :owner, 		Text, 	:required => true   #Whomever created the MapReduce job ie. a researcher
	property :mapFuncLoc,	Text,	:required => true
	property :reduceFuncLoc,Text,	:required => true 
	property :location, 	Text,	:required => true	#Location of the piece of data ie. the link
	property :started,		Boolean, :default => false
	has n, :workers
	has n, :dataChunks
end


class Worker
	include DataMapper::Resource
	property 	:id,		Serial 		#This will be a client/workers unique ID for this job
	property	:dataID,	Integer,	:required => true
	belongs_to 	:job
end

class DataChunk
	include DataMapper::Resource
	property :id, 			Serial
	property :numWorkers,	Integer, :default => 0		#Number of workers who have this piece of data
	property :finished,		Boolean, :default => false 	#Check if we already have the results for this chunk
	belongs_to :job

	#Decides the next chunk to be used in an round-robin scheme.
	def self.nextChunk
		#Chooses the first chunk that has not finished and has the least amount of workers.
		first(:finished => false, :order => [:numWorkers.asc])
	end	
end

DataMapper.finalize.auto_migrate!

#This is just some dummy input for the db to test stuff
test = {
	:desc => "Random description",
	:owner => "Ted Copplestein",
	:mapFuncLoc => "someMapFunc",	
	:reduceFuncLoc => "someReduceFunc",
	:location => "otherdatastore.com/",
	:dataChunks => [
		{
			:numWorkers => 0,
			:finished => false
		},
	]
}
job = Job.first_or_create(test)


test2 = {	
	:desc => "Dummy desc",
	:owner => "Mark Vensawhl",
	:mapFuncLoc => "anotherMapFunc",	
	:reduceFuncLoc => "anotherReduceFunc",
	:location => "datastore.com/",
	:dataChunks => [
		{
			:numWorkers => 0,
			:finished => false
		},
	]
}
blah = Job.first_or_create(test2)

#############################################
#             MR Coordinator                #
#############################################
get '/' do
	@jobs = Job.all(:order => :id.desc)
	erb :home
end

get '/:id/register_job/ready' do
	#Create JSON response with needed info
	content_type :json
	{
		:status => "READY",
		:jobID => params[:id]
	}.to_json

end

get '/register_job/fail' do
	#Create JSON response with needed info
	content_type :json
	{
		:status => "FAIL",
	}.to_json

end

post '/register_job' do
	jobJSON = JSON.parse(request.body.read.to_s)

	newjob = {
		:desc => jobJSON['jobName'],
		:owner => "This is a default value until we change the json format",
		:mapFuncLoc => jobJSON['map'],
		:reduceFuncLoc => jobJSON['reduce'],
		:location => jobJSON['input']
	}
	
	regJob = Job.create(newjob)
	if regJob.saved?
		redirect '/#{regJob.id.to_s}/register_job/ready' #THIS MIGHT NOT WORK. MAY HAVE TO RUN A GET ON THE JOB FIRST
	else
		redirect '/register_job/fail'
	end
end

post '/start_job' do
# json file with the job id to start
	jobIDParse = JSON.parse(request.body.read.to_s)
	jobID = jobIDParse['jobID']
	job = Job.get(jobID)

	job.update(:started => true)
	job.save
end

post '/:id/submit_map_output' do
# post data: 
# {
#    {key: "some_key1", value: ["value1", "value2" ]},
#    {key: "some_key2", value:  ["value1"]},
#    {key: "some_key3", value:  ["value3", "value4"]}
# }
end

get '/:id/worker' do
	#Retrieve the job based on the id
	job = Job.get(params[:id])
	unless job
		redirect '/' #If you can't find the job with that id redirect back to the main page
	end

	nextJob = job.dataChunks.nextChunk #Find next piece of data that needs work
	
	numWorkers = nextJob.numWorkers	#Find out how many workers the dataChunk has
	nextJob.update(:numWorkers => (numWorkers + 1)) #Increment number of workers on the dataChunk
	nextJob.save 
	
	worker = job.workers.create(:dataID => nextJob.id) #Add a worker entry to the job
	
	#Create JSON response with needed info
	content_type :json
	{
		:url => job.location,
		:fnLocation => job.mapFuncLoc, #THIS NEEDS TO BE CHANGED SO IT GIVES THE RIGHT FUNC DEPENDING ON MAP OR EREDUCE PHASE
		:output => job.location,
		:workID => worker.id
	}.to_json
end