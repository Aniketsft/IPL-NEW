using Microsoft.AspNetCore.Mvc;
using EnterpriseAuth.Api.Core.Domain.Entities;
using EnterpriseAuth.Api.Core.Domain.Interfaces;
using EnterpriseAuth.Api.Core.Application.DTOs;

namespace EnterpriseAuth.Api.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class UserGroupsController : ControllerBase
    {
        private readonly IUserGroupRepository _groupRepository;

        public UserGroupsController(IUserGroupRepository groupRepository)
        {
            _groupRepository = groupRepository;
        }

        [HttpGet]
        public async Task<IActionResult> GetAll()
        {
            var groups = await _groupRepository.GetAllAsync();
            var dtos = groups.Select(g => new UserGroupDto
            {
                Id = g.Id,
                Name = g.Name,
                RoleId = g.RoleId
            });
            return Ok(dtos);
        }

        [HttpGet("{id}")]
        public async Task<IActionResult> GetById(Guid id)
        {
            var group = await _groupRepository.GetByIdAsync(id);
            if (group == null) return NotFound();
            
            var dto = new UserGroupDto
            {
                Id = group.Id,
                Name = group.Name,
                RoleId = group.RoleId
            };
            return Ok(dto);
        }

        [HttpPost]
        public async Task<IActionResult> Create([FromBody] UserGroup group)
        {
            await _groupRepository.AddAsync(group);
            return CreatedAtAction(nameof(GetById), new { id = group.Id }, new { id = group.Id, name = group.Name });
        }

        [HttpPut("{id}")]
        public async Task<IActionResult> Update(Guid id, [FromBody] UserGroup group)
        {
            if (id != group.Id) return BadRequest();
            await _groupRepository.UpdateAsync(group);
            return NoContent();
        }

        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(Guid id)
        {
            await _groupRepository.DeleteAsync(id);
            return NoContent();
        }
    }
}
